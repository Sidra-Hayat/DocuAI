import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../datasources/mlkit_text_recognizer.dart';

/// Translates recognition exceptions into `Failure`s.
///
/// Everything becomes an [OcrFailure], including a page image that has gone
/// missing. That is deliberate: `RecognizeDocumentText` reacts to a failure by
/// marking *that page* failed and carrying on, which is the right outcome
/// whether the image was unreadable or absent. Reporting a missing file as a
/// `StorageFailure` would suggest the library itself is broken.
class OcrRepositoryImpl implements OcrRepository {
  const OcrRepositoryImpl(this._recognizer);

  final MlKitTextRecognizer _recognizer;

  @override
  FutureResult<String> recognizeText(String relativeImagePath) async {
    try {
      return Success(await _recognizer.recognize(relativeImagePath));
    } on MlKitException catch (error, stackTrace) {
      return Failed(
        OcrFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } on CacheException catch (error, stackTrace) {
      return Failed(
        OcrFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        OcrFailure(
          'This page could not be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
