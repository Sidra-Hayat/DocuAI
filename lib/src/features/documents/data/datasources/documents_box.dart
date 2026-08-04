import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../models/document_model.dart';

/// Opens the box holding document metadata.
///
/// Lives in the feature rather than in `core/storage`, because
/// [DocumentModel] is a data-layer type of *this* feature and core must not
/// depend on it. `bootstrap()` calls this and injects the result, the same way
/// it handles the settings box.
Future<Box<DocumentModel>> openDocumentsBox() =>
    Hive.openBox<DocumentModel>(HiveBoxes.documents);

/// The opened documents box, injected at startup.
///
/// Deliberately eager rather than an async provider: `watchDocuments()` returns
/// a plain `Stream`, so the box has to be open before the first read. Opening a
/// metadata-only box costs milliseconds, and doing it here spares the library
/// screen a loading state it would show for one frame and never again.
final documentsBoxProvider = Provider<Box<DocumentModel>>(
  (ref) => throw UnimplementedError(
    'documentsBoxProvider was not overridden. '
    'It must be provided by bootstrap() via ProviderScope.overrides.',
  ),
);
