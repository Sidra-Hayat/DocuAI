import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../archives/presentation/screens/archive_screen.dart';
import '../../domain/entities/document.dart';

/// Opens a library item, whatever kind of item it is.
///
/// One function rather than a branch at each call site, because there are two
/// places a library item is tapped — the library itself and a search result —
/// and the day a third appears it should not have to rediscover that archives
/// go somewhere else.
///
/// **An archive opens in the archive browser, not the detail screen.** The
/// detail screen is built around pages: it shows a pager, offers Edit, and
/// starts text recognition. An archive has none of those and one thing the
/// detail screen cannot do at all, which is show what is inside it. That screen
/// already exists, already knows how to read a ZIP safely, and is the same one
/// used for an archive somebody sends from WhatsApp — so a saved archive and a
/// received one open into exactly the same reader.
///
/// The path handed over is absolute, resolved here. Archives are persisted as a
/// path relative to the app documents directory, like every other file this app
/// stores, and only `StoragePaths` knows where that is on this install.
void openLibraryItem(
  BuildContext context,
  WidgetRef ref,
  Document document,
) {
  final relative = document.archivePath;

  if (relative == null) {
    context.pushNamed(
      AppRoutes.documentDetailName,
      pathParameters: <String, String>{'id': document.id},
    );
    return;
  }

  context.pushNamed(
    AppRoutes.archiveName,
    extra: ArchiveArgs(
      path: ref.read(storagePathsProvider).absolutePath(relative),
      name: document.title,
    ),
  );
}
