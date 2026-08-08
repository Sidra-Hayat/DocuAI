import '../../../../core/error/result.dart';

/// Photos chosen from the device, ready to become pages.
///
/// Sits exactly where `ScannerRepository` sits, and returns the same thing:
/// **absolute** paths to temporary files this app does not own yet. That is
/// what lets importing reuse the whole storage path unchanged —
/// `DocumentRepository.createFromImages` and `addPages` already accept
/// precisely this and copy the files in.
abstract interface class ImageImportRepository {
  /// Opens the system picker and returns the chosen images, normalised.
  ///
  /// Backing out without choosing anything returns an empty list rather than a
  /// failure — the same rule the scanner and the share sheet follow, because
  /// cancelling is not an error.
  ///
  /// Files the device can hand over but this app cannot decode are skipped and
  /// named in [ImportOutcome.rejected], with the rest still imported. One
  /// unreadable photo should not cost the user the other nine.
  FutureResult<ImportOutcome> pickImages({int limit});
}

/// What an import produced.
class ImportOutcome {
  const ImportOutcome({required this.imagePaths, this.rejected = const []});

  /// Absolute paths to normalised JPEGs in a temporary directory.
  final List<String> imagePaths;

  /// Names of files that could not be read, for telling the user which.
  final List<String> rejected;

  bool get isEmpty => imagePaths.isEmpty;

  bool get hasRejections => rejected.isNotEmpty;
}
