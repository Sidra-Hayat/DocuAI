import 'dart:io';

import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/router/app_router.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/import/domain/repositories/image_import_repository.dart';
import 'package:docuai/src/features/import/presentation/providers/import_providers.dart';
import 'package:docuai/src/features/incoming/data/datasources/incoming_files_channel.dart';
import 'package:docuai/src/features/incoming/domain/entities/incoming_file.dart';
import 'package:docuai/src/features/incoming/presentation/incoming_files_listener.dart';
import 'package:docuai/src/features/incoming/presentation/providers/incoming_providers.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// "Open with DocuAI", from the Dart side.
///
/// The platform half — copying a content URI into private storage before the
/// grant expires — lives in `IncomingFiles.kt` and cannot be exercised from
/// here. What can, and what these tests cover, is everything that depends on
/// *when* a file arrives and *what* it is:
///
///  * the cold-start backlog, drained through `takePending`, which is the
///    "shared from WhatsApp with the app closed" case;
///  * a file arriving while the app is running, pushed down the same channel;
///  * and the routing decision each one produces — a ZIP browses, a PDF opens
///    for reading, several pictures become one document, and a file DocuAI
///    cannot read says so rather than failing silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_incoming');
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  /// A file on disk, so that anything downstream can actually open it.
  String write(String name) {
    final file = File(p.join(workspace.path, name));
    file.writeAsStringSync('contents of $name');
    return file.path;
  }

  Map<String, Object?> fileMap(String path, {String? mimeType}) =>
      <String, Object?>{
        'path': path,
        'name': p.basename(path),
        'sizeBytes': File(path).lengthSync(),
        'mimeType': mimeType,
      };

  group('reading what the platform sends', () {
    late _FakeChannel platform;
    late IncomingFilesChannel channel;

    setUp(() {
      platform = _FakeChannel();
      channel = IncomingFilesChannel(channel: platform.channel);
    });

    tearDown(() async => channel.dispose());

    test('drains the cold-start backlog', () async {
      final path = write('Invoices.zip');
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[fileMap(path, mimeType: 'application/zip')],
          'rejected': 0,
        },
      ];

      final deliveries = await channel.takePending();

      expect(deliveries, hasLength(1));
      expect(deliveries.single.files.single.name, 'Invoices.zip');
      expect(deliveries.single.files.single.isArchive, isTrue);
    });

    test('an ordinary launch has nothing waiting', () async {
      expect(await channel.takePending(), isEmpty);
    });

    test('a file arriving later comes down the stream', () async {
      final path = write('note.txt');

      final received = channel.deliveries.first;
      await platform.push(<String, Object?>{
        'files': <Object?>[fileMap(path, mimeType: 'text/plain')],
        'rejected': 0,
      });

      expect((await received).files.single.name, 'note.txt');
    });

    test('carries how many of a share could not be copied', () async {
      final path = write('one.jpg');

      final received = channel.deliveries.first;
      await platform.push(<String, Object?>{
        'files': <Object?>[fileMap(path)],
        'rejected': 2,
      });

      expect((await received).rejected, 2);
    });

    test('a malformed payload is ignored, and the channel keeps working', () async {
      final seen = <IncomingDelivery>[];
      final subscription = channel.deliveries.listen(seen.add);
      addTearDown(subscription.cancel);

      // A method channel hands over `Map<Object?, Object?>` whatever was sent,
      // and this is the shape a mismatched platform version would produce. It
      // must not reach the listener, and it must not poison the stream for the
      // next delivery — a bridge that dies on one bad message is a feature that
      // stops working until the app is restarted.
      await platform.push(<String, Object?>{'files': 'not a list'});
      await platform.push(<String, Object?>{
        'files': <Object?>[fileMap(write('after.pdf'))],
        'rejected': 0,
      });

      expect(seen.map((delivery) => delivery.files.single.name), <String>[
        'after.pdf',
      ]);
    });

    test('an entry with no usable path is dropped, not guessed at', () async {
      final good = write('good.pdf');

      final received = channel.deliveries.first;
      await platform.push(<String, Object?>{
        'files': <Object?>[
          <String, Object?>{'path': '', 'name': 'broken'},
          fileMap(good),
        ],
        'rejected': 0,
      });

      expect((await received).files.map((file) => file.name), <String>[
        'good.pdf',
      ]);
    });
  });

  group('deciding where a file goes', () {
    late _FakeChannel platform;
    late FakeDocumentRepository documents;
    late GoRouter router;
    late List<String> visited;

    setUp(() {
      platform = _FakeChannel();
      documents = FakeDocumentRepository();
      visited = <String>[];
    });

    tearDown(() {
      documents.dispose();
      router.dispose();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: Text('the library')),
          ),
          GoRoute(
            path: '/archive',
            name: AppRoutes.archiveName,
            builder: (context, state) {
              visited.add('archive');
              return const Scaffold(body: Text('the archive browser'));
            },
          ),
          GoRoute(
            path: '/opened',
            name: AppRoutes.openedFileName,
            builder: (context, state) {
              visited.add('reader');
              return const Scaffold(body: Text('the reader'));
            },
          ),
          GoRoute(
            path: '/document/:id',
            name: AppRoutes.documentDetailName,
            builder: (context, state) {
              visited.add('document');
              return const Scaffold(body: Text('the document'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            incomingFilesChannelProvider.overrideWithValue(
              IncomingFilesChannel(channel: platform.channel),
            ),
            documentRepositoryProvider.overrideWithValue(documents),
            searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
            imageImportRepositoryProvider.overrideWithValue(
              _FakeImageImporter(),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            scaffoldMessengerKey: IncomingFilesListener.messengerKey,
            builder: (context, child) => IncomingFilesListener(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a ZIP shared on a cold start opens the browser', (
      tester,
    ) async {
      final path = write('Invoices.zip');
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[fileMap(path, mimeType: 'application/zip')],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);

      expect(visited, <String>['archive']);
      // Browsed, not imported. The library is untouched.
      expect(documents.store, isEmpty);
    });

    testWidgets('a ZIP reported as octet-stream still opens the browser', (
      tester,
    ) async {
      // What WhatsApp actually sends. Going by the declared type alone, this is
      // the case that would drop a real user into "cannot open this file".
      final path = write('Invoices.zip');
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[
            fileMap(path, mimeType: 'application/octet-stream'),
          ],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);
      expect(visited, <String>['archive']);
    });

    testWidgets('a ZIP shared while the app is running opens the browser', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(visited, isEmpty);

      final path = write('Later.zip');
      await platform.push(<String, Object?>{
        'files': <Object?>[fileMap(path, mimeType: 'application/zip')],
        'rejected': 0,
      });
      await tester.pumpAndSettle();

      expect(visited, <String>['archive']);
      expect(documents.store, isEmpty);
    });

    testWidgets('a PDF opens for reading rather than importing itself', (
      tester,
    ) async {
      final path = write('Statement.pdf');
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[fileMap(path, mimeType: 'application/pdf')],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);

      expect(visited, <String>['reader']);
      expect(documents.store, isEmpty);
    });

    testWidgets('several pictures become one document', (tester) async {
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[
            fileMap(write('a.jpg'), mimeType: 'image/jpeg'),
            fileMap(write('b.jpg'), mimeType: 'image/jpeg'),
          ],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);

      // One document, not two: a multi-share is one gesture.
      expect(documents.store, hasLength(1));
      expect(visited, <String>['document']);
    });

    testWidgets('a single picture opens for reading, like a PDF', (
      tester,
    ) async {
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[fileMap(write('photo.png'), mimeType: 'image/png')],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);

      expect(visited, <String>['reader']);
      expect(documents.store, isEmpty);
    });

    testWidgets('a file DocuAI cannot read says so and goes nowhere', (
      tester,
    ) async {
      platform.pending = <Object?>[
        <String, Object?>{
          'files': <Object?>[fileMap(write('clip.mp4'), mimeType: 'video/mp4')],
          'rejected': 0,
        },
      ];

      await pumpApp(tester);

      expect(visited, isEmpty);
      expect(find.textContaining('not a kind of file'), findsOneWidget);
    });

    testWidgets('a share where nothing could be copied is reported', (
      tester,
    ) async {
      platform.pending = <Object?>[
        <String, Object?>{'files': <Object?>[], 'rejected': 1},
      ];

      await pumpApp(tester);

      expect(visited, isEmpty);
      expect(find.textContaining('could not be opened'), findsOneWidget);
    });
  });
}

/// Stands in for `IncomingFiles.kt`.
///
/// A real `MethodChannel` over the test messenger rather than a hand-written
/// double, so the payload really is encoded, sent and decoded — which is where
/// a bridge's bugs live.
class _FakeChannel {
  _FakeChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == IncomingFilesChannel.takePendingMethod) {
            final drained = pending;
            pending = <Object?>[];
            return drained;
          }
          return null;
        });
  }

  final MethodChannel channel = const MethodChannel('docuai.test/incoming');

  /// What the activity queued before Dart was listening.
  List<Object?> pending = <Object?>[];

  /// A file arriving while the app is running — `onNewIntent`, in effect.
  Future<void> push(Map<String, Object?> delivery) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall(IncomingFilesChannel.onFilesMethod, delivery),
            ),
            (_) {},
          );
}

/// Normalisation is `image_import_test`'s subject; this only has to hand back
/// pages so the document gets created.
class _FakeImageImporter implements ImageImportRepository {
  @override
  FutureResult<ImportOutcome> pickImages({int limit = 30}) async =>
      const Success(ImportOutcome(imagePaths: <String>[]));

  @override
  FutureResult<ImportOutcome> readImages(
    List<String> paths, {
    int limit = 30,
  }) async => Success(ImportOutcome(imagePaths: paths));
}
