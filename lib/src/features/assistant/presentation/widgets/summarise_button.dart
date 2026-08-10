import 'package:flutter/material.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/entities/assistant_intent.dart';
import '../screens/conversations_screen.dart';

/// Summarises the document, offline, from its own recognised text.
///
/// Opens this document's conversation with the action already chosen. It used
/// to open it with the *sentence* "Summarise this document" typed in, which
/// worked only for as long as the analyser kept recognising that particular
/// phrasing — and which is the same mistake that made the Explain button answer
/// with the words "this document". A [SummarizeDocument] cannot be misread.
///
/// The answer still belongs in the transcript with its citations: a summary the
/// user cannot trace back to the pages it was lifted from is exactly the kind
/// of claim this assistant is built not to make.
class SummariseButton extends StatelessWidget {
  const SummariseButton({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      // A document with no pages has nothing to read. One whose text is not
      // recognised *yet* stays enabled — recognition runs on open, and the
      // assistant explains the wait better than a dead button does.
      onPressed: !document.hasPages
          ? null
          // A fresh thread every time. A summary asked today has nothing to do
          // with one asked last month, and appending them to the same
          // transcript is how a conversation becomes a log nobody reads.
          : () => openNewConversation(
              context,
              documentId: document.id,
              documentTitle: document.title,
              intent: const SummarizeDocument(),
            ),
      icon: const Icon(Icons.subject_outlined),
      label: const Text('Summarise'),
    );
  }
}
