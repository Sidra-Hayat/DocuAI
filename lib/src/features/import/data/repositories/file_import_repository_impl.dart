import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/repositories/file_import_repository.dart';
import '../datasources/document_text_extractor.dart';
import '../datasources/import_scratch.dart';
import '../datasources/imported_image_normalizer.dart';
import '../datasources/pdf_page_rasterizer.dart';

/// Opens the system file picker and returns a path, or null if dismissed.
///
/// A plain function so tests can stand in for the platform channel without a
/// mocking framework, matching how the rest of the app fakes its edges.
typedef FilePickerCall = Future<String?> Function();

/// Android's own document picker, through a plugin with no dependencies of its
/// own beyond Flutter.
///
/// `copyFileToCacheDir` is what makes the result an ordinary file this app can
/// open: what the picker hands back is a content URI belonging to whichever app
/// owns the file, not a path, and a URI grant does not survive the trip into an
/// isolate that wants to decode a JPEG.
Future<String?> _pickWithSystemPicker() => FlutterFileDialog.pickFile(
  params: const OpenFileDialogParams(
    dialogType: OpenFileDialogType.document,
    mimeTypesFilter: FileImportRepositoryImpl.acceptedMimeTypes,
    copyFileToCacheDir: true,
  ),
);

/// Brings a file in and turns it into something the library can hold.
///
/// The conversion happens here rather than in a use case because it is entirely
/// a question of formats and file handles — the layer above needs to know only
/// whether it received pages or text.
class FileImportRepositoryImpl implements FileImportRepository {
  const FileImportRepositoryImpl({
    FilePickerCall picker = _pickWithSystemPicker,
    ImageNormalizer normalizer = normalizeInIsolate,
    PdfPageRasterizer rasterizer = const PdfPageRasterizer(),
    Future<Directory> Function()? temporaryDirectory,
  }) : _pick = picker,
       _normalize = normalizer,
       _rasterizer = rasterizer,
       _tempDir = temporaryDirectory ?? getTemporaryDirectory;

  final FilePickerCall _pick;
  final ImageNormalizer _normalize;
  final PdfPageRasterizer _rasterizer;
  final Future<Directory> Function() _tempDir;

  /// What the picker offers.
  ///
  /// Everything on this list has a path all the way through to a document. A
  /// format the app can pick but not read would be a file chooser that accepts
  /// your file and then tells you it cannot open it, which is worse than not
  /// offering it.
  ///
  /// `.doc` is absent deliberately: the pre-2007 Word format is a binary
  /// container this app has no reader for, and unzipping it fails.
  static const List<String> acceptedMimeTypes = <String>[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain',
    'text/markdown',
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  /// The extensions those types arrive with, which is what actually decides how
  /// a file is read.
  ///
  /// The MIME list above only filters the chooser. Android reports its own type
  /// for a file, and reports it inconsistently — Markdown in particular arrives
  /// as `text/plain`, `text/markdown` or `application/octet-stream` depending on
  /// which app wrote it — so the extension is the more reliable of the two.
  static const List<String> acceptedExtensions = <String>[
    'pdf',
    'docx',
    'txt',
    'md',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  @override
  FutureResult<ImportedFile> pickFile() async {
    try {
      final path = await _pick();

      // Dismissed without choosing. Not a failure; the user knows.
      if (path == null) {
        return const Failed(
          ImportFailure('No file was chosen.', cancelled: true),
        );
      }

      final name = p.basenameWithoutExtension(path);
      final extension = p.extension(path).replaceFirst('.', '').toLowerCase();

      // A chooser can be talked past — some file managers ignore the type
      // filter — so what was actually handed over is checked rather than
      // assumed.
      if (!acceptedExtensions.contains(extension)) {
        return const Failed(
          ImportFailure(
            'That kind of file cannot be imported. DocuAI reads PDFs, Word '
            'files, text files and pictures.',
          ),
        );
      }

      final bytes = await File(path).readAsBytes();

      final directory = await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
      );

      // Stamped so two imports of the same file in one session cannot write
      // over each other's temporary pages.
      final prefix = 'file_${DateTime.now().microsecondsSinceEpoch}';

      switch (extension) {
        case 'pdf':
          final pages = await _rasterizer.rasterize(
            bytes: bytes,
            targetDirectory: directory,
            prefix: prefix,
          );

          if (pages.isEmpty) {
            return const Failed(
              ImportFailure(
                'That PDF could not be opened. It may be damaged, or locked '
                'with a password.',
              ),
            );
          }

          return Success(
            ImportedFile(
              name: name,
              kind: ImportedFileKind.pages,
              imagePaths: pages,
            ),
          );

        case 'docx':
          final text = DocumentTextExtractor.wordDocument(bytes);
          if (text.isEmpty) {
            return const Failed(
              ImportFailure(
                'That Word file could not be read. Only .docx files are '
                'supported — an older .doc can be saved as .docx in Word '
                'first.',
              ),
            );
          }
          return Success(
            ImportedFile(name: name, kind: ImportedFileKind.text, text: text),
          );

        case 'txt':
        case 'md':
          final text = DocumentTextExtractor.plainText(bytes);
          if (text.trim().isEmpty) {
            return const Failed(ImportFailure('That file has no text in it.'));
          }
          return Success(
            ImportedFile(name: name, kind: ImportedFileKind.text, text: text),
          );

        default:
          // An image, through the same normalisation every imported photo
          // gets — upright, bounded in size, re-encoded as JPEG.
          final normalised = await _normalize(
            sourcePath: path,
            targetPath: p.join(directory.path, '$prefix.jpg'),
          );

          if (normalised == null) {
            return const Failed(
              ImportFailure(
                'That picture could not be read. Converting it to JPEG usually '
                'works.',
              ),
            );
          }

          return Success(
            ImportedFile(
              name: name,
              kind: ImportedFileKind.pages,
              imagePaths: <String>[normalised],
            ),
          );
      }
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'That file could not be opened.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
