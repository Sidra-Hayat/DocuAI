import '../../../../core/error/result.dart';

/// Access to the device's document scanner.
///
/// Phase 3 implements this over ML Kit's Document Scanner, which handles edge
/// detection, perspective correction and shadow removal itself — the reason the
/// project has no custom crop pipeline.
abstract interface class ScannerRepository {
  /// Launches the scanner UI and returns the captured pages.
  ///
  /// The returned paths are **absolute** and point at temporary files owned by
  /// the scanner, not by this app. They are only valid until the caller copies
  /// them somewhere permanent, which is what
  /// `DocumentRepository.createFromImages` does.
  ///
  /// A user who backs out without capturing anything gets an empty list rather
  /// than a failure — cancelling is not an error. A missing Play Services
  /// module, however, is a [ScanFailure]: the feature genuinely cannot run.
  AsyncResult<List<String>> scanPages({int pageLimit});

  /// Whether the scanner can actually run on this device.
  ///
  /// ML Kit's scanner is an on-demand Play Services module, so it is absent on
  /// non-GMS devices and on emulator images without the Play Store. Screens
  /// check this before offering the button instead of letting the user find out
  /// by tapping it.
  Future<bool> isAvailable();
}
