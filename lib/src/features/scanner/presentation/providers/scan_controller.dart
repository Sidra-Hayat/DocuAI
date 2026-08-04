import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/utils/clock.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../data/repositories/scanner_repository_impl.dart';
import '../../domain/repositories/scanner_repository.dart';
import '../../domain/usecases/scan_new_document.dart';

// ---- Dependencies ----------------------------------------------------------

/// Phase 8 may override this to force the unavailable path while testing the
/// non-GMS experience on a device that does have Play Services.
final scannerRepositoryProvider = Provider<ScannerRepository>(
  (ref) => const ScannerRepositoryImpl(),
);

/// Whether this device can run the scanner at all.
///
/// Resolved once per screen open rather than cached for the app's lifetime:
/// Play Services can finish installing while DocuAI is running, and a user who
/// fixes the problem should not have to restart the app to be believed.
final scannerAvailabilityProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(scannerRepositoryProvider).isAvailable(),
);

final scanNewDocumentProvider = Provider<ScanNewDocument>(
  (ref) => ScanNewDocument(
    scanner: ref.watch(scannerRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
  ),
);

// ---- State -----------------------------------------------------------------

/// What the scan screen is doing.
///
/// Sealed so the screen's `switch` is checked by the compiler, and so
/// "cancelled" is a state of its own rather than an error the UI has to
/// recognise by its message.
sealed class ScanState {
  const ScanState();
}

/// Nothing started yet, or the user came back from a finished scan.
final class ScanIdle extends ScanState {
  const ScanIdle();
}

/// The native scanner is open, or its pages are being copied in.
final class ScanRunning extends ScanState {
  const ScanRunning();
}

/// The user backed out. Carries no message: they know what they did.
final class ScanCancelled extends ScanState {
  const ScanCancelled();
}

final class ScanSaved extends ScanState {
  const ScanSaved(this.document);

  final Document document;
}

final class ScanFailedState extends ScanState {
  const ScanFailedState(this.message);

  final String message;
}

// ---- Controller ------------------------------------------------------------

class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  /// Runs one scan, from launching the native UI to a saved document.
  ///
  /// Guarded against re-entry: the button is disabled while running, but a
  /// double tap can still land two calls before the first rebuild, and that
  /// would open the scanner twice.
  Future<void> start({Clock clock = systemClock}) async {
    if (state is ScanRunning) return;
    state = const ScanRunning();

    final result = await ref.read(scanNewDocumentProvider)(
      title: defaultTitleFor(clock()),
    );

    state = result.fold(
      onSuccess: ScanSaved.new,
      onFailure: (failure) => failure is ScanFailure && failure.cancelled
          ? const ScanCancelled()
          : ScanFailedState(failure.message),
    );
  }

  /// Returns to idle after the screen has acted on a terminal state, so
  /// re-entering the screen does not immediately replay the last outcome.
  void reset() => state = const ScanIdle();

  /// Titles the document by when it was scanned.
  ///
  /// A date is the only thing known about a document at capture time, and it
  /// beats `ScanNewDocument.defaultTitle` for telling two untitled scans apart
  /// in the library. The user renames it from the detail screen.
  static String defaultTitleFor(DateTime now) =>
      'Scan ${DateFormat('d MMM y, HH:mm').format(now)}';
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
