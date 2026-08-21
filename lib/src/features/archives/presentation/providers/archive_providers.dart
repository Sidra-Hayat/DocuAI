import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../import/presentation/providers/import_providers.dart';
import '../../data/datasources/external_opener.dart';
import '../../data/repositories/archive_repository_impl.dart';
import '../../domain/repositories/archive_repository.dart';
import '../../domain/usecases/import_archive_entries.dart';
import '../../domain/usecases/open_archive.dart';

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => const ArchiveRepositoryImpl(),
);

final openArchiveProvider = Provider<OpenArchive>(
  (ref) => OpenArchive(ref.watch(archiveRepositoryProvider)),
);

final readArchiveEntryProvider = Provider<ReadArchiveEntry>(
  (ref) => ReadArchiveEntry(ref.watch(archiveRepositoryProvider)),
);

/// Importing out of an archive, built on the file importer the Files button
/// already uses. The dependency is the point: there is one import in this app.
final importArchiveEntriesProvider = Provider<ImportArchiveEntries>(
  (ref) => ImportArchiveEntries(
    archives: ref.watch(archiveRepositoryProvider),
    importer: ref.watch(importFileAsDocumentProvider),
  ),
);

final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) => const ExternalOpener(),
);
