import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/repositories/scanner_repository.dart';
import '../datasources/mlkit_document_scanner.dart';
import '../datasources/scanner_availability.dart';

/// Turns the scanner data sources' exceptions into `Failure`s.
///
/// Note what is *not* a failure here: an empty page list. The data source has
/// already converted a cancelled scan into one, and this layer passes it
/// straight through — deciding what an empty capture means belongs to
/// `ScanNewDocument`, which is the only place that knows a document was
/// supposed to come out of it.
class ScannerRepositoryImpl implements ScannerRepository {
  const ScannerRepositoryImpl({
    MlKitDocumentScanner scanner = const MlKitDocumentScanner(),
    ScannerAvailability availability = const ScannerAvailability(),
  }) : _scanner = scanner,
       _availability = availability;

  final MlKitDocumentScanner _scanner;
  final ScannerAvailability _availability;

  @override
  FutureResult<List<String>> scanPages({int pageLimit = 20}) async {
    try {
      return Success(await _scanner.scan(pageLimit: pageLimit));
    } on MlKitException catch (error, stackTrace) {
      return Failed(
        ScanFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        ScanFailure(
          'The document scanner stopped unexpectedly.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<bool> isAvailable() => _availability.isAvailable();
}
