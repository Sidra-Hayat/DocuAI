import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../repositories/export_repository.dart';

/// Shares a document's recognised text as plain text.
///
/// Refuses when there is nothing to share. A share sheet opening on an empty
/// string is worse than a message saying why: the user picks an app, sends
/// nothing, and only finds out at the other end.
class ShareExtractedText {
  const ShareExtractedText(this._export);

  final ExportRepository _export;

  FutureResult<void> call(Document document) {
    // The readable form, not the stored one: text shared into an email or a
    // note must arrive as words rather than as `## Total` and `**248.60**`.
    final text = document.readableText.trim();

    if (text.isEmpty) {
      return Future.value(
        const Failed(
          ExportFailure('There is no recognised text in this document yet.'),
        ),
      );
    }

    // The title travels as the subject so an email or a note arrives named
    // after the document rather than as an untitled wall of text.
    return _export.shareText(text, subject: document.title);
  }
}
