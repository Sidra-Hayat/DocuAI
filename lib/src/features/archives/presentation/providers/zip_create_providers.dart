import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../export/presentation/providers/export_controller.dart';
import '../../data/repositories/zip_builder_repository_impl.dart';
import '../../domain/repositories/zip_builder_repository.dart';
import '../../domain/usecases/create_zip.dart';

/// Wiring for ZIP *creation*, kept apart from `archive_providers.dart`.
///
/// Two files rather than one because they are two features that happen to
/// share a file format. Reading an archive needs nothing but the archive;
/// writing one needs the library, the PDF exporter and the storage paths, and
/// putting those dependencies on the reader's provider file would make every
/// screen that browses a ZIP construct an exporter it never calls.
final zipBuilderRepositoryProvider = Provider<ZipBuilderRepository>(
  (ref) => ZipBuilderRepositoryImpl(
    documents: ref.watch(documentRepositoryProvider),
    // The same exporter the document screen's "Share as PDF" uses. A document
    // inside an archive and a document sent on its own are the same PDF,
    // rendered by the same composer — there is one export in this app.
    export: ref.watch(exportRepositoryProvider),
    paths: ref.watch(storagePathsProvider),
  ),
);

final createZipProvider = Provider<CreateZip>(
  (ref) => CreateZip(ref.watch(zipBuilderRepositoryProvider)),
);

final pickZipFilesProvider = Provider<PickZipFiles>(
  (ref) => PickZipFiles(ref.watch(zipBuilderRepositoryProvider)),
);

final shareZipProvider = Provider<ShareZip>(
  (ref) => ShareZip(ref.watch(zipBuilderRepositoryProvider)),
);
