import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/storage_paths.dart';

/// Wrapper over ML Kit's text recogniser.
///
/// Unlike the document scanner, this model is bundled into the APK rather than
/// downloaded from Play Services, so it works on every device — including the
/// ones where scanning is unavailable and pages arrived from the gallery.
///
/// The native recogniser is created **once and reused**. Recognition is a
/// per-page call, but constructing a detector allocates a native model
/// instance, and doing that for every page of a twenty-page document is twenty
/// allocations to do one batch of work. The instance is released through
/// [close], wired to the provider's disposal.
class MlKitTextRecognizer {
  MlKitTextRecognizer({required StoragePaths paths}) : _paths = paths;

  final StoragePaths _paths;

  TextRecognizer? _recognizer;

  TextRecognizer get _instance =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Recognises text in the page at [relativeImagePath].
  ///
  /// Resolving the stored relative path happens here, which is what keeps
  /// `StoragePaths` — and the whole idea of a file system — out of the domain
  /// layer's OCR use case.
  Future<String> recognize(String relativeImagePath) async {
    final absolutePath = _paths.absolutePath(relativeImagePath);

    // Checked before handing the path to ML Kit, because a missing file
    // otherwise surfaces as an opaque platform error that says nothing about
    // which page failed or why.
    if (!File(absolutePath).existsSync()) {
      throw CacheException(
        'The image for this page is missing from storage.',
      );
    }

    try {
      final recognised = await _instance.processImage(
        InputImage.fromFilePath(absolutePath),
      );
      return recognised.text;
    } on PlatformException catch (error) {
      throw MlKitException(
        'This page could not be read.',
        cause: error,
      );
    } catch (error) {
      // The plugin parses its reply without a null check, so a malformed or
      // absent response throws inside its own deserialisation.
      throw MlKitException('This page could not be read.', cause: error);
    }
  }

  /// Releases the native recogniser. Safe to call when none was created.
  Future<void> close() async {
    final recognizer = _recognizer;
    _recognizer = null;
    if (recognizer == null) return;
    try {
      await recognizer.close();
    } catch (_) {
      // Disposal races with engine teardown in tests and on app exit; there is
      // nothing to recover and nobody left to tell.
    }
  }
}
