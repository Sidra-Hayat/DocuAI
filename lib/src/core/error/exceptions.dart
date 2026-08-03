/// Data-layer exceptions.
///
/// These are thrown by data sources and caught by repository implementations,
/// which convert them into [Failure]s before crossing into the domain layer.
/// Nothing above the data layer should ever catch these directly.
library;

/// Thrown by a local data source when Hive or the file system rejects an
/// operation.
class CacheException implements Exception {
  const CacheException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'CacheException: $message';
}

/// Thrown when a document referenced by id does not exist.
class NotFoundException implements Exception {
  const NotFoundException(this.id);

  final String id;

  @override
  String toString() => 'NotFoundException: no record for id "$id"';
}

/// Thrown when an ML Kit call fails or the underlying Play Services module is
/// unavailable on the device.
class MlKitException implements Exception {
  const MlKitException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'MlKitException: $message';
}
