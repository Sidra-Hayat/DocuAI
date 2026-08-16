import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../documents/presentation/widgets/pick_document_sheet.dart';
import '../../domain/entities/pdf_tool_models.dart';
import '../providers/pdf_tools_providers.dart';
import '../widgets/pdf_tool_result.dart';

/// Choose something to compress, choose how hard, see what it saved.
///
/// The subject can be a PDF anywhere on the phone or a document already in the
/// library. Restricting it to the library — which is what this did — made the
/// tool useless for the case people actually have: a PDF someone sent them that
/// is too big to send on.
class CompressPdfScreen extends ConsumerStatefulWidget {
  const CompressPdfScreen({super.key});

  @override
  ConsumerState<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends ConsumerState<CompressPdfScreen> {
  /// Exactly one of these is set once a subject has been chosen.
  Document? _document;
  PdfSource? _file;

  CompressionLevel _level = CompressionLevel.balanced;

  bool _busy = false;
  ToolProgress? _progress;
  CompressionOutcome? _outcome;

  bool get _hasSubject => _document != null || _file != null;

  String get _subjectTitle => _document?.title ?? _file?.name ?? '';

  String get _subjectDetail {
    final document = _document;
    if (document != null) {
      return '${document.pageCount} '
          '${document.pageCount == 1 ? 'page' : 'pages'} · in your library';
    }

    final file = _file;
    if (file != null) return '${formatBytes(file.sizeBytes)} · on this device';

    return 'A PDF on this phone, or a document you already have';
  }

  /// Offers the two places a PDF can come from, and names them accurately.
  ///
  /// The wording matters more than it looks. This opens Android's *document*
  /// picker — Files, Downloads, Drive — and not the photo gallery, and a label
  /// that says "choose a file" while the phone shows a document browser is the
  /// difference between a user who finds their PDF and one who goes looking in
  /// their photos for it.
  Future<void> _chooseSubject() async {
    await showAppActionSheet(
      context,
      title: 'What would you like to compress?',
      actions: <AppSheetAction>[
        AppSheetAction(
          icon: Icons.folder_open_outlined,
          label: 'A PDF on this phone',
          description: 'Opens your files — Downloads, Drive, anywhere a PDF is',
          onSelected: _pickFile,
        ),
        AppSheetAction(
          icon: Icons.description_outlined,
          label: 'A document in DocuAI',
          description: 'Something you scanned or imported already',
          onSelected: _pickDocument,
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(pickPdfProvider)();

    switch (result) {
      case Success(:final value):
        if (!mounted) return;
        setState(() {
          _file = value;
          _document = null;
          _outcome = null;
        });
      case Failed(:final failure):
        // Backing out of the picker is not a failure worth reporting.
        if (failure is ImportFailure && failure.cancelled) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _pickDocument() async {
    final document = await pickDocument(
      context,
      title: 'Compress which document?',
      emptyMessage:
          'Nothing in your library has pages to compress yet. You can still '
          'choose a PDF from this phone.',
      // Only documents made of page images. A written document is already
      // text — a few kilobytes — and offering to compress it would be an offer
      // that cannot pay off.
      where: (document) => document.hasImagePages,
    );

    if (document == null || !mounted) return;
    setState(() {
      _document = document;
      _file = null;
      _outcome = null;
    });
  }

  Future<void> _compress() async {
    final document = _document;
    final file = _file;
    if (document == null && file == null) return;

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _busy = true;
      _outcome = null;
      _progress = const ToolProgress(done: 0, total: 1);
    });

    void onProgress(ToolProgress progress) {
      if (mounted) setState(() => _progress = progress);
    }

    final result = document != null
        ? await ref.read(compressDocumentProvider)(
            document: document,
            level: _level,
            onProgress: onProgress,
          )
        : await ref.read(compressPdfFileProvider)(
            source: file!,
            level: _level,
            onProgress: onProgress,
          );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });

    switch (result) {
      case Success(:final value):
        setState(() => _outcome = value);
      case Failed(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// Throws away a copy the user does not want to keep.
  ///
  /// Only reachable for a copy that *was* smaller and therefore saved — one
  /// that came out no smaller was never written. Only ever removes the copy;
  /// whatever was compressed is untouched by the compression and by this.
  Future<void> _discard(Document saved) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref.read(deleteDocumentProvider)(saved.id);

    if (!mounted) return;

    switch (result) {
      case Success():
        setState(() => _outcome = null);
        messenger.showSnackBar(
          const SnackBar(content: Text('The compressed copy was removed.')),
        );
      case Failed(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;

    if (_busy) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compress')),
        body: AppStateView.busy(
          title: (_progress?.label.isNotEmpty ?? false)
              ? 'Compressing — ${_progress!.label}'
              : 'Compressing…',
          progress: _progress?.fraction,
        ),
      );
    }

    if (outcome != null) {
      final saved = outcome.document;

      // Nothing was written, so there is nothing to view, share or delete. The
      // result is a sentence and a way out — offering View here would offer the
      // document the user already has under a name suggesting it is new.
      if (saved == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Compressed')),
          body: AppStateView(
            icon: Icons.check_circle_outline,
            title: 'This document is already optimized',
            message:
                'The compressed version would not be smaller — '
                '${formatBytes(outcome.originalBytes)} against '
                '${formatBytes(outcome.compressedBytes)} at '
                '${outcome.level.label.toLowerCase()}. Nothing was saved, and '
                '"${outcome.sourceLabel}" is unchanged. Try "Smaller size" for '
                'a bigger reduction.',
            action: FilledButton(
              onPressed: () => setState(() => _outcome = null),
              child: const Text('Done'),
            ),
          ),
        );
      }

      final percent = (outcome.savedFraction * 100).round();

      return Scaffold(
        appBar: AppBar(title: const Text('Compressed')),
        body: PdfToolResult(
          title: 'Saved $percent%',
          summary:
              'Original ${formatBytes(outcome.originalBytes)}  →  '
              'Compressed ${formatBytes(outcome.compressedBytes)}',
          detail:
              'Saved as "${saved.title}". '
              '"${outcome.sourceLabel}" is unchanged.',
          document: saved,
          onDone: () => setState(() => _outcome = null),
          extraActions: <Widget>[
            AppSpacing.gapSm,
            TextButton.icon(
              onPressed: () => _discard(saved),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete this copy'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Compress')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          // Edge-to-edge: without the system inset the last control sits under
          // the gesture bar.
          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          Text(
            'Works on any PDF on your phone, not just the ones in DocuAI. A '
            'smaller copy is saved as a new document and the original is left '
            'exactly as it is.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          AppSpacing.gapLg,
          _SubjectChoice(
            title: _hasSubject ? _subjectTitle : 'Choose a PDF or document',
            detail: _subjectDetail,
            chosen: _hasSubject,
            fromDevice: _file != null,
            onPressed: _chooseSubject,
          ),
          if (_hasSubject) ...<Widget>[
            AppSpacing.gapXl,
            Text(
              'How small?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            AppSpacing.gapSm,
            RadioGroup<CompressionLevel>(
              groupValue: _level,
              onChanged: (chosen) => setState(() => _level = chosen ?? _level),
              child: Column(
                children: <Widget>[
                  for (final level in CompressionLevel.values)
                    RadioListTile<CompressionLevel>(
                      value: level,
                      title: Text(level.label),
                      subtitle: Text(level.description),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            AppSpacing.gapLg,
            FilledButton.icon(
              onPressed: _compress,
              icon: const Icon(Icons.compress_outlined),
              label: const Text('Compress'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectChoice extends StatelessWidget {
  const _SubjectChoice({
    required this.title,
    required this.detail,
    required this.chosen,
    required this.fromDevice,
    required this.onPressed,
  });

  final String title;
  final String detail;
  final bool chosen;
  final bool fromDevice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.card,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Icon(
                // Says where it came from at a glance: a folder for a file off
                // the phone, a page for something already in the library.
                !chosen
                    ? Icons.add_circle_outline
                    : fromDevice
                    ? Icons.folder_open_outlined
                    : Icons.description_outlined,
                color: theme.colorScheme.secondary,
              ),
              AppSpacing.gapHorizontalMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
