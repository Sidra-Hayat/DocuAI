import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';

/// PDF composition and sharing.
///
/// Phase 5 implements this with the `pdf` and `share_plus` packages. Both
/// methods stay on this one interface because they are always used together:
/// there is no flow in the app that builds a PDF without offering to share it.
abstract interface class ExportRepository {
  /// Renders [document]'s pages into a PDF and writes it inside the document's
  /// own folder.
  ///
  /// Returns the **relative** path to the file, which the caller stores on
  /// `Document.pdfPath`. Overwrites any previous export: the PDF is a derived
  /// artefact, so keeping stale copies would only waste space on a device with
  /// no way to garbage-collect them.
  FutureResult<String> buildPdf(Document document);

  /// Opens the Android share sheet for a file already inside the app's storage.
  ///
  /// Takes a relative path for the same reason the rest of the app does. A user
  /// who dismisses the sheet without choosing a target is a success — the
  /// system gives no way to distinguish that from a completed share, and
  /// treating it as an error would show a spurious message.
  FutureResult<void> shareFile(String relativePath, {String? subject});
}
