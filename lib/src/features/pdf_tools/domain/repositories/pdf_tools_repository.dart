import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../entities/pdf_tool_models.dart';

/// Working on PDFs offline, using the renderer Android already has.
///
/// Both tools produce a **new** DocuAI document and never touch what went in.
/// That is not caution for its own sake: a merge reads files that belong to
/// other apps, and a compression that overwrote the document it was given would
/// destroy the only high-quality copy the moment the user chose the wrong
/// setting.
abstract interface class PdfToolsRepository {
  /// Opens the system picker for one PDF.
  ///
  /// One at a time because that is what the platform picker this app uses
  /// offers — `flutter_file_dialog` returns a single path, and the multi-select
  /// picker that would replace it cannot be added without breaking the Android
  /// build. The merge screen calls this repeatedly instead, which imposes no
  /// limit of its own on how many files a merge may hold.
  ///
  /// A dismissed picker comes back as a cancelled `ImportFailure`, which the
  /// caller passes over in silence.
  FutureResult<PdfSource> pickPdf();

  /// Renders every page of [sources], in the order given, into one document.
  ///
  /// Page order is the order of [sources] and, within each, the order of its
  /// own pages. Nothing is reordered or de-duplicated on the way through.
  FutureResult<MergeOutcome> merge({
    required List<PdfSource> sources,
    required String title,
    ToolProgressCallback? onProgress,
  });

  /// Re-encodes [document]'s pages at [level] and saves them as a new document.
  ///
  /// The copy is kept whether or not it came out smaller — see
  /// [CompressionOutcome] — and the document that went in is never touched.
  FutureResult<CompressionOutcome> compress({
    required Document document,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  });

  /// The same, for a PDF that is not in the library yet.
  ///
  /// Compression is deliberately not restricted to documents DocuAI made. The
  /// file is rendered through the same path an import takes, so a PDF picked
  /// from device storage and one already in the library reach the compressor as
  /// the same thing, and the file the user picked is only ever read.
  FutureResult<CompressionOutcome> compressPdfFile({
    required PdfSource source,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  });
}
