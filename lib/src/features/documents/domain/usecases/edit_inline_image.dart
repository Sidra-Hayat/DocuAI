import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../import/data/datasources/import_scratch.dart';
import '../../data/datasources/inline_image_transformer.dart';
import '../repositories/document_repository.dart';

/// Applies a rotation and a crop to a picture already in a document.
///
/// **Writes a new file rather than overwriting the old one**, and returns its
/// name for the caller to put in the text. Three reasons, in order of how much
/// trouble each would otherwise cause:
///
///  * Flutter caches decoded images by path. Overwriting in place leaves the
///    editor showing the picture as it was until something evicts the entry —
///    the user crops, taps Save, and nothing appears to happen.
///  * A crash between writing and saving the text would leave the document
///    pointing at a file that is neither the original nor a saved edit.
///  * The old file needs no special handling: the moment the text stops naming
///    it, the sweep that already runs on every save removes it.
///
/// The document's own storage is the only place either file lives, so the
/// result survives a restart for the same reason the original did.
class EditInlineImage {
  const EditInlineImage({
    required DocumentRepository documents,
    required StoragePaths paths,
    InlineImageEditor transformer = transformInIsolate,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documents = documents,
       _paths = paths,
       _transform = transformer,
       _tempDir = temporaryDirectory;

  final DocumentRepository _documents;
  final StoragePaths _paths;
  final InlineImageEditor _transform;
  final Future<Directory> Function()? _tempDir;

  /// Scratch space of its own, kept apart from the importer's and the PDF
  /// tools': `ImportScratch.prepare` empties the folder it is given.
  static const String scratchDirectory = 'docuai_image_edit';

  /// Returns the new picture's file name, or a failure the editor can show.
  FutureResult<String> call({
    required String documentId,
    required String imageName,
    required InlineImageEdit edit,
  }) async {
    // Nothing asked for. Returning the name unchanged means Save on an
    // untouched picture is free rather than a re-encode that loses a little
    // quality and orphans a perfectly good file.
    if (edit.isIdentity) return Success(imageName);

    try {
      final source = File(_paths.inlineImagePath(documentId, imageName));
      if (!source.existsSync()) {
        return const Failed(
          StorageFailure(
            'That picture is no longer on this device, so it cannot be edited.',
          ),
        );
      }

      final scratch = await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
        name: scratchDirectory,
      );

      final edited = await _transform(
        sourcePath: source.path,
        targetPath: p.join(scratch.path, 'edited.jpg'),
        edit: edit,
      );

      if (edited == null) {
        return const Failed(
          StorageFailure('That picture could not be read, so it was not '
              'changed.'),
        );
      }

      // Copied into the document's own folder under a fresh name, by the same
      // method the picker's output goes through. The original is left alone
      // until the save that stops referring to it.
      return _documents.addInlineImage(
        documentId: documentId,
        sourcePath: edited,
      );
    } catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'That picture could not be changed.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
