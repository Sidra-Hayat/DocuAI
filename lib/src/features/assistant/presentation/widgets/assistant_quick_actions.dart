import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import '../../domain/entities/assistant_intent.dart';

/// The things people come to an assistant to do, as actions rather than as
/// sentences.
///
/// Every one of these used to send the English it was labelled with — "Explain
/// this document" — into the same pipeline a typed question goes down. The
/// engine then did what it is built to do and looked for those words on a page,
/// which is how tapping Explain came to answer:
///
/// ```
/// This passage says:
/// “this document”
/// ```
///
/// A button knows what it means. It now says so, in [AssistantIntent], and
/// nothing between here and the repository has to work it out again.
///
/// They appear twice: large, in the empty state, where they say what this
/// screen is for; and behind one button beside the composer afterwards, because
/// the need for them does not end with the first question.
class AssistantQuickActions extends StatelessWidget {
  const AssistantQuickActions({
    required this.onIntent,
    required this.onWriteQuestion,
    required this.scoped,
    super.key,
  });

  /// Carries out a chosen action.
  final ValueChanged<AssistantIntent> onIntent;

  /// Puts the caret in the composer. "Ask" is not a canned request; it is an
  /// invitation to write one.
  final VoidCallback onWriteQuestion;

  /// True in a conversation about one document.
  ///
  /// Summarise and Explain need something to be about. Offering them on the
  /// library-wide conversation would be offering an action whose only possible
  /// answer is "open a document first".
  final bool scoped;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: <Widget>[
        ActionChip(
          avatar: const Icon(Icons.help_outline, size: 18),
          label: const Text('Ask'),
          onPressed: onWriteQuestion,
        ),
        for (final action in AssistantActions.headline(scoped))
          ActionChip(
            avatar: Icon(action.icon, size: 18),
            label: Text(action.label),
            onPressed: () => onIntent(action.intent),
          ),
      ],
    );
  }
}

/// The same actions, as a sheet, for the button beside the composer.
Future<void> showQuickActionsSheet(
  BuildContext context, {
  required bool scoped,
  required ValueChanged<AssistantIntent> onIntent,
  required VoidCallback onWriteQuestion,
}) {
  return showAppActionSheet(
    context,
    title: 'What would you like to know?',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.help_outline,
        label: 'Ask',
        description: 'Write your own question',
        onSelected: onWriteQuestion,
      ),
      for (final action in AssistantActions.all(scoped))
        AppSheetAction(
          icon: action.icon,
          label: action.label,
          description: action.description,
          onSelected: () => onIntent(action.intent),
        ),
    ],
  );
}

/// One offered action: what it is called, and what it means.
class AssistantAction {
  const AssistantAction({
    required this.icon,
    required this.label,
    required this.intent,
    this.description,
  });

  final IconData icon;
  final String label;
  final String? description;
  final AssistantIntent intent;
}

/// The catalogue.
///
/// One list, so the chips and the sheet cannot drift apart, and so adding an
/// action later is a line here rather than an edit in three places.
abstract final class AssistantActions {
  /// The few worth showing without being asked.
  static List<AssistantAction> headline(bool scoped) => <AssistantAction>[
    if (scoped) ...<AssistantAction>[_summarize(scoped), _explain(scoped)],
    _important,
    _find(InformationKind.names, Icons.person_outline),
    _find(InformationKind.dates, Icons.event_outlined),
  ];

  /// Everything, for the sheet.
  static List<AssistantAction> all(bool scoped) => <AssistantAction>[
    if (scoped) ...<AssistantAction>[_summarize(scoped), _explain(scoped)],
    _important,
    _find(InformationKind.names, Icons.person_outline),
    _find(InformationKind.dates, Icons.event_outlined),
    _find(InformationKind.amounts, Icons.payments_outlined),
    _find(InformationKind.locations, Icons.place_outlined),
    _find(InformationKind.references, Icons.tag_outlined),
    _find(InformationKind.contacts, Icons.alternate_email_outlined),
  ];

  static AssistantAction _summarize(bool scoped) => AssistantAction(
    icon: Icons.subject_outlined,
    label: scoped ? 'Summarise document' : 'Summarise',
    description: 'The main points, in the document’s own words',
    intent: const SummarizeDocument(),
  );

  static AssistantAction _explain(bool scoped) => AssistantAction(
    icon: Icons.lightbulb_outline,
    label: scoped ? 'Explain document' : 'Explain',
    description: 'What this document is and what it covers',
    intent: const ExplainDocument(),
  );

  static const AssistantAction _important = AssistantAction(
    icon: Icons.fact_check_outlined,
    label: 'Find important information',
    description: 'Dates, amounts, names and reference numbers',
    intent: FindInformation(InformationKind.important),
  );

  static AssistantAction _find(InformationKind kind, IconData icon) =>
      AssistantAction(
        icon: icon,
        label: kind.transcriptLabel,
        intent: FindInformation(kind),
      );
}
