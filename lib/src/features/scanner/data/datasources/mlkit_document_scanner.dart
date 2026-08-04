import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../../../../core/error/exceptions.dart';

/// Thin wrapper over ML Kit's document scanner.
///
/// Exists to contain three things the plugin gets wrong for our purposes:
///
///  * **Cancelling arrives as an error.** The Android side answers
///    `RESULT_CANCELED` with `result.error("DocumentScanner", "Operation
///    cancelled")`, so backing out of the scanner would otherwise reach the
///    repository as a platform exception. Here it becomes an empty list, which
///    is what `ScannerRepository` promises its callers.
///  * **Scanner instances leak.** Each Dart `DocumentScanner` gets a
///    timestamp id and is stored in a map on the Kotlin side until `close()`
///    removes it. One scan per instance, always closed.
///  * **Nothing distinguishes "unreadable result" from a crash.** Anything
///    unexpected becomes a [MlKitException] so the repository has one type to
///    catch.
class MlKitDocumentScanner {
  const MlKitDocumentScanner();

  /// Launches the scanner UI and returns absolute paths to the captured pages.
  ///
  /// The paths point at files in the app's cache directory, owned by the
  /// scanner. They must be copied — not moved — before they can be relied on.
  Future<List<String>> scan({required int pageLimit}) async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        // JPEG only. The scanner can emit a PDF too, but DocuAI composes its
        // own in Phase 5 from the stored pages, so asking for one here would
        // produce a file that goes stale the moment a page is deleted.
        documentFormats: const {DocumentFormat.jpeg},
        // Full mode is what gives auto-capture, edge detection and the filter
        // set — the reason this project has no custom crop pipeline.
        mode: ScannerMode.full,
        pageLimit: pageLimit,
        // Also the practical fallback on devices whose camera the scanner
        // cannot drive: the user can still bring in an existing photo.
        isGalleryImport: true,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      return List<String>.unmodifiable(result.images ?? const <String>[]);
    } on PlatformException catch (error) {
      if (_isCancellation(error)) return const <String>[];
      throw MlKitException(_messageFor(error), cause: error);
    } catch (error) {
      throw MlKitException(
        'The document scanner could not be started.',
        cause: error,
      );
    } finally {
      // Closing only removes the instance from the plugin's map, so it cannot
      // fail meaningfully — but it runs on a channel that may itself be gone
      // (a widget test, a detached engine), and a throw here would mask the
      // real outcome.
      try {
        await scanner.close();
      } catch (_) {
        // Nothing to recover: the scan result, or its failure, is what matters.
      }
    }
  }

  /// The plugin reports cancellation as an error carrying this message. There
  /// is no code to match on — every failure it raises uses `"DocumentScanner"`
  /// — so the message is the only signal available.
  static bool _isCancellation(PlatformException error) =>
      (error.message ?? '').toLowerCase().contains('cancel');

  static String _messageFor(PlatformException error) {
    final detail = (error.message ?? '').toLowerCase();
    if (detail.contains('failed to start')) {
      // Overwhelmingly the Play Services module failing to resolve rather than
      // anything about this particular scan.
      return 'The scanner could not start. It needs Google Play Services, '
          'which may still be downloading.';
    }
    return 'The document scanner stopped unexpectedly.';
  }
}
