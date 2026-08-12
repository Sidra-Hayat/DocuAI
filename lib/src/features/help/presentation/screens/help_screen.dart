import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// What each part of DocuAI is for, in the words someone would use before they
/// knew any of them.
///
/// Written for the person who has just installed the app, which rules out most
/// of the vocabulary the app is built from. No "OCR" — the app *reads the text
/// on a page*. No "retrieval" or "index" — the assistant *looks through your
/// documents*. Nothing here explains how anything works, because a first-run
/// guide that explains the machinery is a guide for the person who wrote it.
///
/// Six sections, in the order someone meets them: get a document in, do
/// something with it, find it again.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('How DocuAI works')),
      body: ListView(
        // The list always scrolled; what it did not do was leave room for the
        // system navigation. `bootstrap()` puts the app in
        // `SystemUiMode.edgeToEdge`, so the window extends under the gesture
        // bar — and a scroll view whose content ends at its own padding ends
        // *underneath* it. The last section could be scrolled to and still not
        // be readable, which on a phone reads as text simply missing.
        //
        // Taken from the view rather than assumed: the inset is a three-button
        // bar on one phone, a gesture pill on another, and zero in landscape on
        // a third. Nothing here is a fixed height, and nothing was made smaller
        // to fit.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          // The promise first. It is the reason someone would keep their
          // payslips in this app rather than in the one with more features.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: AppRadius.surface,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                AppSpacing.gapHorizontalMd,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Everything stays on your phone',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      AppSpacing.gapXs,
                      Text(
                        'There is no account and no upload. Your documents are '
                        'only ever on this device, and they are deleted when '
                        'you uninstall the app.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.gapXl,

          const _Step(
            icon: Icons.document_scanner_outlined,
            title: 'Scan',
            body:
                'Point your camera at a page and DocuAI takes the picture, '
                'straightens it and trims the edges for you. It then reads the '
                'words on the page so you can search them later.\n\n'
                'Best results come from a flat page in good light.',
          ),
          const _Step(
            icon: Icons.photo_library_outlined,
            title: 'Import',
            body:
                'Already have a photo of the page? Bring it in from your '
                'gallery and DocuAI treats it exactly like a scan.\n\n'
                'You can also bring in a PDF, a Word file or a text file. A PDF '
                'becomes pages you can read and search.',
          ),
          const _Step(
            icon: Icons.edit_note_outlined,
            title: 'Create a document',
            body:
                'Write something yourself — notes, a list, a draft. You can '
                'make text bold, add headings and bullet points, and drop in '
                'pictures from your phone.\n\n'
                'It saves as you type, so there is no save button to remember.',
          ),
          const _Step(
            icon: Icons.auto_awesome_outlined,
            title: 'Assistant',
            body:
                'Ask about your documents in your own words — "what is this '
                'about?", "how much do I owe?", "what dates are mentioned?".\n\n'
                'Every answer comes from your own pages and shows you which '
                'document and page it came from, so you can check it. If the '
                'answer is not in your documents, it says so rather than '
                'making something up.',
          ),
          const _Step(
            icon: Icons.search,
            title: 'Search',
            body:
                'Search finds words *inside* your documents, not just their '
                'titles. Type part of a phrase and it shows you the documents '
                'that contain it, with the matching words highlighted.\n\n'
                'Put quotation marks around words to find them together.',
          ),
          const _Step(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF and sharing',
            body:
                'Any document can be turned into a PDF and sent through email, '
                'messaging or anywhere else on your phone. Pictures you added '
                'come through in the PDF too.\n\n'
                'Documents with text can also be sent as a Word file if '
                'someone needs to edit them.',
            last: true,
          ),
        ],
      ),
    );
  }
}

/// One thing the app does, and what it means for the person using it.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Suppresses the divider, so the list does not end on a rule with nothing
  /// under it.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppRadius.card,
              ),
              child: Icon(
                icon,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            AppSpacing.gapHorizontalMd,
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        AppSpacing.gapMd,
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
        if (!last) ...<Widget>[
          AppSpacing.gapXl,
          Divider(color: theme.colorScheme.outlineVariant),
          AppSpacing.gapXl,
        ],
      ],
    );
  }
}

