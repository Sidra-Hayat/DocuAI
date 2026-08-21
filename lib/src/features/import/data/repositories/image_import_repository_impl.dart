import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/repositories/image_import_repository.dart';
import '../datasources/import_scratch.dart';
import '../datasources/imported_image_normalizer.dart';

/// Picks photos and hands back normalised temporary files.
///
/// The picker itself is a plain function so tests can stand in for the platform
/// channel without a mocking framework, matching how the rest of the app fakes
/// its edges.
typedef ImagePickerCall = Future<List<XFile>> Function({int? limit});

Future<List<XFile>> _pickWithSystemPicker({int? limit}) =>
    ImagePicker().pickMultiImage(limit: limit);

class ImageImportRepositoryImpl implements ImageImportRepository {
  const ImageImportRepositoryImpl({
    ImagePickerCall picker = _pickWithSystemPicker,
    ImageNormalizer normalizer = normalizeInIsolate,
    Future<Directory> Function()? temporaryDirectory,
  }) : _pick = picker,
       _normalize = normalizer,
       _tempDir = temporaryDirectory ?? getTemporaryDirectory;

  final ImagePickerCall _pick;
  final ImageNormalizer _normalize;
  final Future<Directory> Function() _tempDir;

  /// Photos accepted in one go.
  ///
  /// Not a technical limit — a bound on how long the user waits staring at a
  /// progress indicator, and on how much a single mistaken tap can add.
  static const int defaultLimit = 30;

  @override
  FutureResult<ImportOutcome> pickImages({int limit = defaultLimit}) async {
    try {
      final picked = await _pick(limit: limit);

      // Dismissed without choosing. Not a failure; the user knows.
      if (picked.isEmpty) {
        return const Success(ImportOutcome(imagePaths: <String>[]));
      }

      return _normalizeAll(
        picked
            .take(limit)
            .map((file) => (path: file.path, name: file.name))
            .toList(),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'The photos could not be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<ImportOutcome> readImages(
    List<String> paths, {
    int limit = defaultLimit,
  }) async {
    if (paths.isEmpty) {
      return const Success(ImportOutcome(imagePaths: <String>[]));
    }

    try {
      return _normalizeAll(
        paths
            .take(limit)
            .map((path) => (path: path, name: p.basename(path)))
            .toList(),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'Those pictures could not be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Makes every picture upright, bounded and JPEG, in the scratch directory.
  ///
  /// The one place that does it, whether the pictures came from the picker or
  /// from another app's share sheet. A second copy of this loop would be a
  /// second answer to what a page is.
  Future<Result<ImportOutcome>> _normalizeAll(
    List<({String path, String name})> sources,
  ) async {
    final directory = await ImportScratch.prepare(temporaryDirectory: _tempDir);

    final normalised = <String>[];
    final rejected = <String>[];

    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final target = p.join(
        directory.path,
        'import_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
      );

      final written = await _normalize(
        sourcePath: source.path,
        targetPath: target,
      );

      // One unreadable photo — HEIC, most often — must not cost the user the
      // other nine. Named rather than counted, so they know which to convert.
      if (written == null) {
        rejected.add(source.name);
        continue;
      }
      normalised.add(written);
    }

    return Success(ImportOutcome(imagePaths: normalised, rejected: rejected));
  }
}
