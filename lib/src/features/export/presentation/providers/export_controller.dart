import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../data/repositories/export_repository_impl.dart';
import '../../domain/repositories/export_repository.dart';
import '../../domain/usecases/export_document_as_pdf.dart';
import '../../domain/usecases/share_document.dart';

// ---- Dependencies ----------------------------------------------------------

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepositoryImpl(paths: ref.watch(storagePathsProvider)),
);

final exportDocumentAsPdfProvider = Provider<ExportDocumentAsPdf>(
  (ref) => ExportDocumentAsPdf(
    export: ref.watch(exportRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
  ),
);

final shareDocumentProvider = Provider<ShareDocument>(
  (ref) => ShareDocument(
    export: ref.watch(exportRepositoryProvider),
    exportAsPdf: ref.watch(exportDocumentAsPdfProvider),
  ),
);

// ---- State -----------------------------------------------------------------

sealed class ExportState {
  const ExportState();

  String? get documentId => null;
}

final class ExportIdle extends ExportState {
  const ExportIdle();
}

/// Composing the PDF, or waiting on the share sheet.
final class ExportRunning extends ExportState {
  const ExportRunning(this.documentId);

  @override
  final String documentId;
}

final class ExportFailedState extends ExportState {
  const ExportFailedState(this.documentId, this.message);

  @override
  final String documentId;

  final String message;
}

// ---- Controller ------------------------------------------------------------

class ExportController extends Notifier<ExportState> {
  @override
  ExportState build() => const ExportIdle();

  /// Shares the document as a PDF, composing one first if needed.
  ///
  /// Set [rebuild] to discard the recorded PDF and compose a fresh one — the
  /// retry path when the previous export has been removed from storage, which
  /// Android is free to do to a file the user has already shared.
  Future<void> shareAsPdf(Document document, {bool rebuild = false}) async {
    if (state is ExportRunning) return;
    state = ExportRunning(document.id);

    var target = document;

    if (rebuild) {
      final rebuilt = await ref.read(exportDocumentAsPdfProvider)(document.id);
      switch (rebuilt) {
        case Failed(:final failure):
          state = ExportFailedState(document.id, failure.message);
          return;
        case Success(:final value):
          target = value;
      }
    }

    final result = await ref.read(shareDocumentProvider)(target);

    state = result.fold(
      // Back to idle rather than a "shared" state: the sheet has closed and
      // there is nothing left for the screen to report.
      onSuccess: (_) => const ExportIdle(),
      onFailure: (failure) => ExportFailedState(document.id, failure.message),
    );
  }

  void reset() => state = const ExportIdle();
}

final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
