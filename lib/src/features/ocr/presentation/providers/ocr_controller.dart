import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/datasources/mlkit_text_recognizer.dart';
import '../../data/repositories/ocr_repository_impl.dart';
import '../../domain/repositories/ocr_repository.dart';
import '../../domain/usecases/recognize_document_text.dart';

// ---- Dependencies ----------------------------------------------------------

final mlKitTextRecognizerProvider = Provider<MlKitTextRecognizer>((ref) {
  final recognizer = MlKitTextRecognizer(paths: ref.watch(storagePathsProvider));
  // Releases the native model when nothing is using it any more.
  ref.onDispose(recognizer.close);
  return recognizer;
});

final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => OcrRepositoryImpl(ref.watch(mlKitTextRecognizerProvider)),
);

final recognizeDocumentTextProvider = Provider<RecognizeDocumentText>(
  (ref) => RecognizeDocumentText(
    ocr: ref.watch(ocrRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
    search: ref.watch(searchRepositoryProvider),
  ),
);

// ---- State -----------------------------------------------------------------

/// What text recognition is doing, and for which document.
///
/// The document id travels with the state because one controller serves
/// whichever document is open. A screen compares it against its own id and
/// ignores anything else, so a run that outlives a navigation cannot paint
/// progress onto the wrong document.
sealed class OcrState {
  const OcrState();

  String? get documentId => null;
}

final class OcrIdle extends OcrState {
  const OcrIdle();
}

final class OcrRunning extends OcrState {
  const OcrRunning({
    required this.documentId,
    required this.done,
    required this.total,
  });

  @override
  final String documentId;

  /// Pages finished, and how many this run will touch — not the document's
  /// total, since a re-run may only cover the pages that failed.
  final int done;
  final int total;

  double? get fraction => total == 0 ? null : done / total;
}

final class OcrCompleted extends OcrState {
  const OcrCompleted(this.documentId);

  @override
  final String documentId;
}

final class OcrFailedState extends OcrState {
  const OcrFailedState(this.documentId, this.message);

  @override
  final String documentId;

  final String message;
}

// ---- Controller ------------------------------------------------------------

class OcrController extends Notifier<OcrState> {
  @override
  OcrState build() => const OcrIdle();

  /// Recognises text across a document's outstanding pages.
  ///
  /// Only the load-or-save failure ends up in [OcrFailedState] — individual
  /// unreadable pages are recorded on the pages themselves by the use case and
  /// stay retryable, so a document with one bad photo still reports success and
  /// keeps the text it did get.
  Future<void> run(String documentId, {bool force = false}) async {
    if (state case OcrRunning(documentId: final running) when running == documentId) {
      return;
    }

    state = OcrRunning(documentId: documentId, done: 0, total: 0);

    final result = await ref.read(recognizeDocumentTextProvider)(
      documentId,
      force: force,
      onProgress: (done, total) {
        // A run that is superseded by another document's must not keep
        // repainting the first one's progress.
        if (state.documentId != documentId) return;
        state = OcrRunning(documentId: documentId, done: done, total: total);
      },
    );

    if (state.documentId != documentId) return;

    state = result.fold(
      onSuccess: (_) => OcrCompleted(documentId),
      onFailure: (failure) => OcrFailedState(documentId, failure.message),
    );
  }

  void reset() => state = const OcrIdle();
}

final ocrControllerProvider = NotifierProvider<OcrController, OcrState>(
  OcrController.new,
);
