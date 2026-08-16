import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../export/presentation/widgets/share_sheet.dart';

/// Whether the result is straightforwardly good.
enum PdfToolResultTone {
  /// It worked. Nothing to qualify.
  success,

  /// It worked, with something the user needs to know — pages left out, or a
  /// file that could not be made smaller.
  caution,
}

/// What a finished PDF job offers next.
///
/// Shared by merge and compress because they finish the same way: a document
/// exists, and the user wants to look at it, send it, or go back. Two copies of
/// this would be two places for the navigation bug below to come back.
///
/// **The navigation here is the fix for the Navigator assertion.** Both tool
/// screens are pushed on the root navigator, while the document detail route
/// lives inside the documents branch of the `StatefulShellRoute`. Reaching it
/// with `push` or `pushReplacement` makes GoRouter build a page list holding
/// `/documents` twice — once as the branch already underneath, once as the
/// parent of the detail page going on top — and Navigator asserts on the
/// duplicate page key.
///
/// `go` has no such problem: it rebuilds the stack declaratively from the
/// target location, so the result is exactly `/documents` → `/documents/detail`
/// with the tool routes gone. Back from the document then lands on the library,
/// which is where somebody who has finished merging wants to be.
class PdfToolResult extends ConsumerWidget {
  const PdfToolResult({
    required this.title,
    required this.summary,
    required this.detail,
    required this.document,
    required this.onDone,
    this.tone = PdfToolResultTone.success,
    this.extraActions = const <Widget>[],
    super.key,
  });

  /// The headline: what happened.
  final String title;

  /// The figures — page counts, or sizes.
  final String summary;

  /// Where it was saved, and what was left alone.
  final String detail;

  /// The document that was produced, and which View and Share act on.
  final Document document;

  /// Clears the result and returns the screen to its starting state.
  final VoidCallback onDone;

  final PdfToolResultTone tone;

  /// Anything the individual tool wants to offer beyond View and Share.
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final good = tone == PdfToolResultTone.success;

    final background = good
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.tertiaryContainer;
    final foreground = good
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onTertiaryContainer;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // The app draws edge to edge, so a scroll view that stops at its own
        // padding stops underneath the gesture bar.
        AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    good ? Icons.check_circle_outline : Icons.info_outline,
                    color: foreground,
                  ),
                  AppSpacing.gapHorizontalSm,
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              Text(
                summary,
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
              AppSpacing.gapSm,
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapXl,
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                // Declarative, not imperative — see the class comment.
                onPressed: () =>
                    context.go(AppRoutes.documentDetailPath(document.id)),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View'),
              ),
            ),
            AppSpacing.gapHorizontalSm,
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => showShareSheet(context, ref, document),
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
        ...extraActions,
        AppSpacing.gapMd,
        TextButton(
          // Pops nothing and pushes nothing: it clears the result and hands the
          // screen back to the user, who can leave with the system Back gesture
          // like every other screen in the app.
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
