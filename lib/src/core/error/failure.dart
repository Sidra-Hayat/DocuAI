/// Domain-level error type.
///
/// The domain layer never sees a `HiveError`, a `PlatformException` or an
/// `IOException`. The data layer catches those and maps them onto one of the
/// subtypes below, which keeps the domain pure Dart and makes error handling
/// exhaustively checkable by the compiler:
///
/// ```dart
/// final message = switch (failure) {
///   StorageFailure() => 'Could not read your documents.',
///   ScanFailure()    => 'Scanning was cancelled.',
///   // the analyzer errors if a case is missing
/// };
/// ```
sealed class Failure {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Human-readable, already-localised description safe to show to the user.
  final String message;

  /// The original error, kept for logging. Never surfaced in the UI.
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// Reading from or writing to local storage failed (Hive or the file system).
final class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause, super.stackTrace});
}

/// The document scanner failed or was dismissed by the user.
/// Importing photos from the device went wrong.
///
/// Separate from [ScanFailure] because the two fail for different reasons and
/// the messages have to say different things — a missing Play Services module
/// is not the same problem as a photo this app cannot decode.
final class ImportFailure extends Failure {
  const ImportFailure(
    super.message, {
    this.cancelled = false,
    super.cause,
    super.stackTrace,
  });

  /// True when the picker was dismissed rather than something going wrong.
  /// Reported silently, for the reason given on [ScanFailure.cancelled].
  final bool cancelled;
}

final class ScanFailure extends Failure {
  const ScanFailure(
    super.message, {
    this.cancelled = false,
    super.cause,
    super.stackTrace,
  });

  /// True when the user backed out of the scanner instead of something going
  /// wrong. There is no document to show either way, so it still travels as a
  /// failure — but the UI must stay silent rather than report a problem the
  /// user already knows about, having caused it.
  final bool cancelled;
}

/// Text recognition failed on one or more pages.
final class OcrFailure extends Failure {
  const OcrFailure(super.message, {super.cause, super.stackTrace});
}

/// PDF composition or export failed.
final class ExportFailure extends Failure {
  const ExportFailure(super.message, {super.cause, super.stackTrace});
}

/// A required runtime permission was denied.
final class PermissionFailure extends Failure {
  const PermissionFailure(
    super.message, {
    this.permanentlyDenied = false,
    super.cause,
    super.stackTrace,
  });

  /// When true the user selected "don't ask again" and must be sent to the
  /// system settings page rather than re-prompted.
  final bool permanentlyDenied;
}

/// Input rejected by a use case before any repository was called — an empty
/// title, a blank question. Distinct from the failures above because nothing
/// went wrong technically: the user simply needs to change what they typed.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.cause, super.stackTrace});
}

/// The offline assistant could not produce an answer.
final class AssistantFailure extends Failure {
  const AssistantFailure(super.message, {super.cause, super.stackTrace});
}

/// Anything that escaped the cases above. Should be rare; investigate if seen.
final class UnexpectedFailure extends Failure {
  /// [message] is named here rather than positional so it can carry a default
  /// while still allowing [cause] and [stackTrace] — Dart does not permit
  /// optional positional and named parameters in the same signature.
  const UnexpectedFailure({
    String message = 'Something went wrong.',
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message, cause: cause, stackTrace: stackTrace);
}
