import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/datasources/document_local_data_source.dart';
import '../../data/datasources/documents_box.dart';
import '../../data/repositories/document_repository_impl.dart';
import '../../domain/entities/document.dart';
import '../../domain/repositories/document_repository.dart';
import '../../domain/usecases/delete_document.dart';
import '../../domain/usecases/rename_document.dart';
import '../../domain/usecases/toggle_favorite.dart';
import '../../domain/usecases/update_document_tags.dart';
import '../../domain/usecases/watch_documents.dart';

/// Dependency graph for the document library.
///
/// Written by hand rather than with `@riverpod` codegen: these are plain
/// constructor calls with no generated argument classes to earn back the build
/// step. The generator is reserved for providers that take parameters, where it
/// removes real boilerplate.

// ---- Data layer ------------------------------------------------------------

final documentLocalDataSourceProvider = Provider<DocumentLocalDataSource>(
  (ref) => DocumentLocalDataSource(
    box: ref.watch(documentsBoxProvider),
    paths: ref.watch(storagePathsProvider),
  ),
);

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepositoryImpl(ref.watch(documentLocalDataSourceProvider)),
);

// ---- Reads -----------------------------------------------------------------

/// The library, newest first. Every screen showing documents watches this one
/// stream, so a rename on the detail screen is visible in the list behind it.
final documentsProvider = StreamProvider<List<Document>>(
  (ref) => WatchDocuments(ref.watch(documentRepositoryProvider))(),
);

/// A single document, derived from [documentsProvider] rather than read
/// separately.
///
/// Deriving means the detail screen updates when the document changes and —
/// more importantly — resolves to `null` the moment it is deleted, so the
/// screen can pop itself instead of rendering a record that no longer exists.
final documentProvider = Provider.family<AsyncValue<Document?>, String>(
  (ref, id) => ref.watch(documentsProvider).whenData((documents) {
    for (final document in documents) {
      if (document.id == id) return document;
    }
    return null;
  }),
);

// ---- Actions ---------------------------------------------------------------

final renameDocumentProvider = Provider<RenameDocument>(
  (ref) => RenameDocument(ref.watch(documentRepositoryProvider)),
);

final toggleFavoriteProvider = Provider<ToggleFavorite>(
  (ref) => ToggleFavorite(ref.watch(documentRepositoryProvider)),
);

final updateDocumentTagsProvider = Provider<UpdateDocumentTags>(
  (ref) => UpdateDocumentTags(ref.watch(documentRepositoryProvider)),
);

final deleteDocumentProvider = Provider<DeleteDocument>(
  (ref) => DeleteDocument(
    documents: ref.watch(documentRepositoryProvider),
    search: ref.watch(searchRepositoryProvider),
  ),
);
