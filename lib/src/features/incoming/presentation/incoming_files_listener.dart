import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/app_routes.dart';
import '../../archives/domain/entities/archive_entry.dart';
import '../../archives/presentation/screens/archive_screen.dart';
import '../../archives/presentation/screens/file_reader_screen.dart';
import '../../import/presentation/providers/import_providers.dart';
import '../domain/entities/incoming_file.dart';
import 'providers/incoming_providers.dart';

/// Watches for files other apps hand over, and decides where each one goes.
///
/// Mounted once, above everything, because a hand-over can arrive at any moment
/// and must not depend on which screen happens to be open. It draws nothing —
/// it is its child and a subscription.
///
/// **The three arrival states, from this side.**
///
///  * *Cold start.* [initState] calls `takePending`, which drains whatever the
///    activity queued while the Dart isolate was still starting. This is the
///    WhatsApp-with-the-app-closed case, and it is the one that needs a queue
///    at all: the file was copied before this widget existed.
///  * *Warm.* The subscription below is live, `onNewIntent` fires on the
///    platform side, and the delivery arrives on the stream.
///  * *From the background.* Identical to warm — the activity is alive, so it
///    is `onNewIntent` again. The only difference is that Android brings the
///    task forward first, which is its business rather than this widget's.
///
/// All three end at [_route], so there is one answer to "what happens when a
/// ZIP arrives" rather than three that have to be kept in step.
class IncomingFilesListener extends ConsumerStatefulWidget {
  const IncomingFilesListener({required this.child, super.key});

  final Widget child;

  /// Handed to `MaterialApp.router` so this widget can raise a message without
  /// a `Scaffold` of its own. It sits above the navigator and has no route
  /// context to reach a messenger through.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>(debugLabel: 'incoming');

  @override
  ConsumerState<IncomingFilesListener> createState() =>
      _IncomingFilesListenerState();
}

class _IncomingFilesListenerState extends ConsumerState<IncomingFilesListener> {
  StreamSubscription<IncomingDelivery>? _subscription;

  /// Guards the *decision*, not the screen it opens.
  ///
  /// Two files handed over in quick succession would otherwise race each other
  /// onto the navigator, and the second would land on top of a screen the first
  /// was still building. It is released as soon as a route has been pushed —
  /// deliberately not when that route is closed. A pushed route's future
  /// completes on *pop*, so holding the guard for it would mean a second ZIP
  /// shared while the first was still open being dropped in silence, which is
  /// exactly the case "works while the app is already running" has to cover.
  bool _handling = false;

  @override
  void initState() {
    super.initState();

    final channel = ref.read(incomingFilesChannelProvider);
    _subscription = channel.deliveries.listen(_onDelivery);

    // After the first frame, not during it. Pushing a route from `initState`
    // means asking a navigator that has not been built yet.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      for (final delivery in await channel.takePending()) {
        await _route(delivery);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onDelivery(IncomingDelivery delivery) => unawaited(_route(delivery));

  Future<void> _route(IncomingDelivery delivery) async {
    if (_handling) return;
    _handling = true;

    try {
      if (delivery.isEmpty) {
        _say(
          delivery.rejected > 0
              ? 'That file could not be opened. It may have been moved, or be '
                    'too large for DocuAI to copy in.'
              : 'Nothing was shared.',
        );
        return;
      }

      if (delivery.rejected > 0) {
        _say(
          '${delivery.rejected} of the shared files could not be read and '
          'were skipped.',
        );
      }

      final first = delivery.files.first;

      // A ZIP is browsed, never imported on sight. This is the whole feature:
      // the user wants to know what is in it, and the answer to that is a list,
      // not thirty new documents.
      if (first.isArchive) {
        _openArchive(first);
        return;
      }

      // Several pictures shared together are one gesture, so they become one
      // document — the same thing a multi-selection in the photo picker does.
      if (delivery.files.length > 1 && delivery.isAllImages) {
        await _importImages(delivery.files);
        return;
      }

      _openForReading(first);
    } finally {
      _handling = false;
    }
  }

  void _openArchive(IncomingFile file) {
    // Not awaited: see [_handling]. The push itself is synchronous enough that
    // the next delivery cannot overtake it.
    unawaited(
      _router().pushNamed<void>(
        AppRoutes.archiveName,
        extra: ArchiveArgs(path: file.path, name: file.name),
      ),
    );
  }

  /// Opens a single file for reading, with an import offered on the screen.
  ///
  /// Not imported here. A PDF someone sent is a thing to look at first; whether
  /// it is worth keeping is a decision the user makes after seeing it, which is
  /// exactly what the reader's "Add to library" is for.
  void _openForReading(IncomingFile file) {
    final kind = kindForName(file.name);

    if (!kind.isReadable) {
      _say(
        '"${file.name}" is not a kind of file DocuAI can open. It reads PDFs, '
        'pictures, text files and ZIP archives.',
      );
      return;
    }

    unawaited(
      _router().pushNamed<void>(
        AppRoutes.openedFileName,
        extra: FileReaderArgs(path: file.path, title: file.name, kind: kind),
      ),
    );
  }

  /// Several shared pictures, as one document.
  ///
  /// Through `ImportImagesAsDocument`, which is the same use case the Photos
  /// button uses — the pictures are normalised, made upright and bounded in
  /// exactly the same way, and what lands in the library is indistinguishable
  /// from a gallery import.
  Future<void> _importImages(List<IncomingFile> files) async {
    final result = await ref
        .read(importImagesAsDocumentProvider)
        .fromPaths(
          files.map((file) => file.path).toList(),
          title: _sharedTitle(),
        );

    if (!mounted) return;

    switch (result) {
      case Failed(:final failure):
        if (failure is ImportFailure && failure.cancelled) return;
        _say(failure.message);
      case Success(:final value):
        if (value.rejected.isNotEmpty) {
          _say(
            '${value.rejected.length} of those pictures could not be read.',
          );
        }
        unawaited(
          _router().pushNamed<void>(
            AppRoutes.documentDetailName,
            pathParameters: <String, String>{'id': value.document.id},
          ),
        );
    }
  }

  GoRouter _router() => ref.read(appRouterProvider);

  void _say(String message) => IncomingFilesListener.messengerKey.currentState
      ?.showSnackBar(SnackBar(content: Text(message)));

  /// Shared photographs are named after the day they arrived, exactly as
  /// imported ones are. Renameable from then on, like any document.
  static String _sharedTitle() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return 'Shared $day/$month/${now.year}';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
