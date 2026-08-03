import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

/// Resolves on-disk locations for scanned pages and generated PDFs.
///
/// **Everything persisted in Hive stores a *relative* path** and converts it
/// through [absolutePath] at read time. Android does not guarantee the absolute
/// sandbox path is stable across reinstalls or app updates, so persisting
/// absolute paths is the classic cause of "all my documents vanished" reports.
class StoragePaths {
  const StoragePaths(this._appDocumentsDir);

  final Directory _appDocumentsDir;

  /// Root folder holding one subfolder per document.
  Directory get documentsRoot =>
      Directory(p.join(_appDocumentsDir.path, AppConstants.documentsDirName));

  /// Folder for a single document, created on demand.
  Future<Directory> documentDir(String documentId) async {
    final dir = Directory(p.join(documentsRoot.path, documentId));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Converts a stored relative path into a usable absolute path.
  String absolutePath(String relativePath) =>
      p.join(_appDocumentsDir.path, relativePath);

  /// Converts an absolute path into the form that is safe to persist.
  String relativePath(String absolutePath) =>
      p.relative(absolutePath, from: _appDocumentsDir.path);

  /// Deletes a document's folder and every page inside it.
  Future<void> deleteDocumentDir(String documentId) async {
    final dir = Directory(p.join(documentsRoot.path, documentId));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}

/// Injected at startup by `bootstrap()`, for the same reasons described in
/// `storage_providers.dart`.
final storagePathsProvider = Provider<StoragePaths>(
  (ref) => throw UnimplementedError(
    'storagePathsProvider was not overridden. '
    'It must be provided by bootstrap() via ProviderScope.overrides.',
  ),
);

/// Resolves the platform documents directory. Called once during startup.
Future<StoragePaths> createStoragePaths() async =>
    StoragePaths(await getApplicationDocumentsDirectory());
