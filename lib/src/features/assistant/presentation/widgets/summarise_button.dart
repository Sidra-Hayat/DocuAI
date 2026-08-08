import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/usecases/suggest_questions.dart';

/// Summarises the document, offline, from its own recognised text.
///
/// Opens this document's conversation with the question already asked, rather
/// than running a summariser of its own. That is deliberate: the button and
/// someone typing "summarise this" must produce the same result, and the answer
/// belongs in the transcript with its citations — a summary the user cannot
/// trace back to the pages it was lifted from is exactly the kind of claim this
/// assistant is built not to make.
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
          : () => context.pushNamed(
              AppRoutes.askDocumentName,
              pathParameters: <String, String>{'id': document.id},
              queryParameters: <String, String>{
                'title': document.title,
                'ask': DocumentQuestions.summarise,
              },
            ),
      icon: const Icon(Icons.subject_outlined),
      label: const Text('Summarise'),
    );
  }
}
