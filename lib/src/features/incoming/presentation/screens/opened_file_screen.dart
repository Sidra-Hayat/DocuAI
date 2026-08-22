import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../archives/presentation/screens/file_reader_screen.dart';
import '../../../import/presentation/providers/import_providers.dart';

/// A single file another app handed over, opened for reading.
///
/// The same reader the archive browser uses, plus the one thing that only makes
/// sense here: a way to keep the file. Somebody who taps a PDF in WhatsApp and
/// chooses DocuAI wants to *see* it — importing every such file on sight would
/// fill the library with things nobody chose — but having seen it, "keep this"
/// is the obvious next thought, and it should not mean going back to WhatsApp
/// and starting again.
///
/// So the reader is the screen and the import is a button on it. This class
/// exists to own that button: the reader itself has no providers, no library
/// and no opinion about storage, which is what keeps it usable from inside an
/// archive where importing means something different.
class OpenedFileScreen extends ConsumerStatefulWidget {
  const OpenedFileScreen({required this.args, super.key});

  final FileReaderArgs args;

  @override
  ConsumerState<OpenedFileScreen> createState() => _OpenedFileScreenState();
}

class _OpenedFileScreenState extends ConsumerState<OpenedFileScreen> {
  bool _importing = false;

  Future<void> _import() async {
    // Guarded rather than debounced. The button is in an app bar that stays put
    // while a PDF renders, and a double tap would otherwise produce two
    // identical documents.
    if (_importing) return;
    setState(() => _importing = true);

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final result = await ref
        .read(importFileAsDocumentProvider)
        .fromPath(widget.args.path, title: _titleFor(widget.args.title));

    if (!mounted) return;
    setState(() => _importing = false);

    switch (result) {
      case Failed(:final failure):
        if (failure is ImportFailure && failure.cancelled) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      case Success(:final value):
        if (value.truncatedAt case final kept?) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'That PDF is longer than DocuAI can import. The first $kept '
                'pages were brought in; the rest were not.',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }

        // Replaces the reader rather than stacking on it. The file is now a
        // document, and a Back that returned to a read-only copy of it would be
        // going backwards through the same content twice.
        //
        // Not awaited: the future completes when the *document* screen is
        // eventually popped, which is not something this method is waiting for.
        unawaited(router.pushReplacementNamed<void>(
          AppRoutes.documentDetailName,
          pathParameters: <String, String>{'id': value.document.id},
        ));
    }
  }

  /// The file's name without its extension. `Statement.pdf` is a better library
  /// row as "Statement" than as "Statement.pdf".
  static String _titleFor(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    return stem.trim().isEmpty ? name : stem.trim();
  }

  @override
  Widget build(BuildContext context) =>
      FileReaderScreen(args: widget.args, onImport: _importing ? null : _import);
}
