import '../../../../core/error/result.dart';

/// On-device text recognition.
///
/// Phase 4 implements this over ML Kit Text Recognition, which — unlike the
/// document scanner — is bundled into the app rather than downloaded from Play
/// Services, so it works on any device.
abstract interface class OcrRepository {
  /// Recognises text in a single page image.
  ///
  /// [relativeImagePath] is the path as stored on the page entity; resolving it
  /// against the app documents directory happens inside the implementation, so
  /// that no use case has to touch `StoragePaths` and the domain layer stays
  /// free of file-system concepts.
  ///
  /// An empty string is a valid success: a photograph of a blank page contains
  /// no text, and that is a result, not an error.
  FutureResult<String> recognizeText(String relativeImagePath);
}
