import 'package:docuai/src/core/router/app_router.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guard that keeps a file URI from becoming a destination.
///
/// Written after a real-device bug: opening a ZIP from WhatsApp launched DocuAI
/// straight onto "We could not open that page — GoException: no routes for
/// location: content://com.whatsapp.provider.media/item/e417…". Android's
/// embedding hands `intent.getData()` to the framework as the initial route,
/// and the router did what it was told.
///
/// The manifest now turns that behaviour off at the source. These tests cover
/// the second lock: whatever a future Flutter version, a new intent filter or a
/// cached engine decides to hand over, a location that is not one of this app's
/// own paths lands on the library rather than on an error screen.
void main() {
  group('locations that came from outside the app', () {
    test('a content URI from a sharing app goes to the library', () {
      expect(
        redirectForeignLocation(
          Uri.parse(
            'content://com.whatsapp.provider.media/item/'
            'e4174024-1f7e-4c3a-9a6d-0b3d5f8e2c11',
          ),
        ),
        AppRoutes.documents,
      );
    });

    test('a file URI goes to the library', () {
      expect(
        redirectForeignLocation(
          Uri.parse('file:///sdcard/Download/folders.zip'),
        ),
        AppRoutes.documents,
      );
    });

    test('an http URL goes to the library', () {
      // No App Links are declared, but a BROWSABLE filter makes this reachable
      // enough to be worth refusing rather than reasoning about.
      expect(
        redirectForeignLocation(Uri.parse('https://example.com/documents')),
        AppRoutes.documents,
      );
    });

    test('a scheme-relative location goes to the library', () {
      expect(
        redirectForeignLocation(Uri.parse('//evil.example/documents')),
        AppRoutes.documents,
      );
    });

    test('a relative location goes to the library', () {
      expect(redirectForeignLocation(Uri.parse('documents')), AppRoutes.documents);
    });
  });

  group('the app\'s own locations are left alone', () {
    test('every branch of the shell', () {
      for (final path in <String>[
        AppRoutes.documents,
        AppRoutes.search,
        AppRoutes.assistant,
      ]) {
        expect(redirectForeignLocation(Uri.parse(path)), isNull, reason: path);
      }
    });

    test('the full-screen routes, including the archive browser', () {
      for (final path in <String>[
        AppRoutes.settings,
        AppRoutes.scan,
        AppRoutes.help,
        AppRoutes.pdfTools,
        AppRoutes.archive,
        AppRoutes.openedFile,
        '${AppRoutes.archive}/${AppRoutes.archiveEntry}',
      ]) {
        expect(redirectForeignLocation(Uri.parse(path)), isNull, reason: path);
      }
    });

    test('nested paths with parameters and a query string', () {
      for (final path in <String>[
        AppRoutes.documentDetailPath('abc-123'),
        AppRoutes.extractedTextPath('abc-123'),
        AppRoutes.pageViewerPath('abc-123', 4),
        AppRoutes.managePagesPath('abc-123'),
        AppRoutes.editPagePath('abc-123', 'page-1'),
        '${AppRoutes.conversationPath('c-1')}?document=abc-123&title=Notes',
      ]) {
        expect(redirectForeignLocation(Uri.parse(path)), isNull, reason: path);
      }
    });

    test('the root, which is what the platform sends on an ordinary launch', () {
      // With deep linking off, this is the initial route Android now hands
      // over. It must not be redirected — GoRouter turns "/" into the
      // configured initialLocation itself.
      expect(redirectForeignLocation(Uri.parse('/')), isNull);
    });
  });
}
