import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import '../../domain/usecases/suggest_questions.dart';

/// The four things people come to an assistant to do.
///
/// Ask, Summarize, Explain, Important information. Every one of them is a
/// question routed through the same analyser as a typed one — there is no
/// second code path, which is what keeps a button and a sentence producing the
/// same answer with the same citations.
///
/// They appear twice: large, in the empty state, where they say what this
/// screen is for; and behind one button beside the composer afterwards, because
/// the need for them does not end with the first question — the old screen
/// showed its suggestions once and then took them away for good.
class AssistantQuickActions extends StatelessWidget {
  const AssistantQuickActions({
    required this.onAsk,
    required this.onWriteQuestion,
    required this.scoped,
    super.key,
  });

  /// Sends a question as though it had been typed.
  final ValueChanged<String> onAsk;

  /// Puts the caret in the composer. "Ask" is not a canned question; it is an
  /// invitation to write one.
  final VoidCallback onWriteQuestion;

  /// True in a conversation about one document.
  ///
  /// Summarize and Explain need something to be about. Offering them on the
  /// library-wide conversation would be offering a question the assistant can
  /// only answer with "which document?".
  final bool scoped;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (final action in _actions(scoped))
          ActionChip(
            avatar: Icon(action.icon, size: 18),
            label: Text(action.label),
            onPressed: () => action.run(context, onAsk, onWriteQuestion),
          ),
      ],
    );
  }
}

/// The same actions, as a sheet, for the button beside the composer.
Future<void> showQuickActionsSheet(
  BuildContext context, {
  required bool scoped,
  required ValueChanged<String> onAsk,
  required VoidCallback onWriteQuestion,
}) {
  return showAppActionSheet(
    context,
    title: 'What would you like to know?',
    actions: <AppSheetAction>[
      for (final action in _actions(scoped))
        AppSheetAction(
          icon: action.icon,
          label: action.label,
          description: action.description,
          onSelected: () => action.run(context, onAsk, onWriteQuestion),
        ),
    ],
  );
}

/// Everything the assistant can be asked for by name.
///
/// "Important information" opens a second sheet rather than guessing: dates,
/// amounts, names and reference numbers are four different questions, and one
/// button that silently picks one of them would be answering something the user
/// did not ask.
List<_QuickAction> _actions(bool scoped) => <_QuickAction>[
  _QuickAction(
    icon: Icons.help_outline,
    label: 'Ask',
    description: 'Write your own question',
    run: (context, onAsk, onWrite) => onWrite(),
  ),
  if (scoped) ...<_QuickAction>[
    _QuickAction(
      icon: Icons.subject_outlined,
      label: 'Summarize',
      description: 'The main points, in the document’s own words',
      run: (context, onAsk, onWrite) => onAsk(DocumentQuestions.summarise),
    ),
    _QuickAction(
      icon: Icons.lightbulb_outline,
      label: 'Explain',
      description: 'What this document is saying',
      run: (context, onAsk, onWrite) => onAsk('Explain this document'),
    ),
  ],
  _QuickAction(
    icon: Icons.fact_check_outlined,
    label: 'Important information',
    description: 'Dates, amounts, names or reference numbers',
    run: (context, onAsk, onWrite) => _showDetailSheet(context, onAsk),
  ),
];

Future<void> _showDetailSheet(
  BuildContext context,
  ValueChanged<String> onAsk,
) {
  return showAppActionSheet(
    context,
    title: 'Find important information',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.event_outlined,
        label: 'Dates',
        onSelected: () => onAsk(DocumentQuestions.dates),
      ),
      AppSheetAction(
        icon: Icons.payments_outlined,
        label: 'Amounts',
        onSelected: () => onAsk(DocumentQuestions.amounts),
      ),
      AppSheetAction(
        icon: Icons.person_outline,
        label: 'Names',
        onSelected: () => onAsk(DocumentQuestions.names),
      ),
      AppSheetAction(
        icon: Icons.tag_outlined,
        label: 'Reference numbers',
        onSelected: () => onAsk(DocumentQuestions.references),
      ),
      AppSheetAction(
        icon: Icons.alternate_email_outlined,
        label: 'Contact details',
        onSelected: () => onAsk(DocumentQuestions.contact),
      ),
    ],
  );
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.run,
  });

  final IconData icon;
  final String label;
  final String description;
  final void Function(
    BuildContext context,
    ValueChanged<String> onAsk,
    VoidCallback onWriteQuestion,
  )
  run;
}
