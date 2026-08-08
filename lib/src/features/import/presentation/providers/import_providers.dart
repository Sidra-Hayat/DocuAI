import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../documents/presentation/providers/document_providers.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/repositories/image_import_repository_impl.dart';
import '../../domain/repositories/image_import_repository.dart';
import '../../domain/usecases/import_images.dart';

final imageImportRepositoryProvider = Provider<ImageImportRepository>(
  (ref) => const ImageImportRepositoryImpl(),
);

final importImagesAsDocumentProvider = Provider<ImportImagesAsDocument>(
  (ref) => ImportImagesAsDocument(
    importer: ref.watch(imageImportRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
  ),
);

final importImagesIntoDocumentProvider = Provider<ImportImagesIntoDocument>(
  (ref) => ImportImagesIntoDocument(
    importer: ref.watch(imageImportRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
    search: ref.watch(searchRepositoryProvider),
  ),
);
