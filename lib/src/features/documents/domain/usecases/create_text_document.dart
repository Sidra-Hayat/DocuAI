import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';
import 'rename_document.dart';

/// Creates a document to be written rather than scanned.
///
/// Deliberately not a separate kind of thing. What comes back is an ordinary
/// [Document] holding an ordinary page, so renaming, tagging, favouriting,
/// deleting, searching, exporting and asking the assistant about it all work
/// through the code that already existed — none of which knows a text document
/// from a scan.
class CreateTextDocument {
  const CreateTextDocument(this._repository);

  final DocumentRepository _repository;

  /// Used when the user creates one without naming it.
  ///
  /// A default rather than a rejection: someone who wants to start writing
  /// should not be stopped at a title field, and the title is renameable from
  /// the moment the document exists.
  static const String defaultTitle = 'Untitled document';

  FutureResult<Document> call({String title = defaultTitle}) async {
    final trimmed = title.trim();

    // The same rule [RenameDocument] enforces, referenced rather than repeated:
    // a title that could not be renamed *to* must not be creatable *with*.
    if (trimmed.length > RenameDocument.maxTitleLength) {
      return const Failed(
        ValidationFailure(
          'That title is too long — keep it under 120 characters.',
        ),
      );
    }

    return _repository.createTextDocument(
      title: trimmed.isEmpty ? defaultTitle : trimmed,
    );
  }
}
