import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/domain/usecases/ask_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeAssistantRepository repository;
  late AskAssistant ask;
  late int idCounter;

  setUp(() {
    idCounter = 0;
    repository = FakeAssistantRepository();
    ask = AskAssistant(
      repository,
      idGenerator: () => 'id-${++idCounter}',
      clock: fixedClock,
    );
  });

  test('records the question and the answer as two turns', () async {
    repository.answer = const Success(
      AssistantAnswer(
        text: 'The deadline is 14 August.',
        citations: <AnswerCitation>[
          AnswerCitation(
            documentId: 'doc-1',
            documentTitle: 'Lecture notes',
            pageIndex: 2,
            snippet: '…submit by 14 August…',
          ),
        ],
      ),
    );

    final result = await ask('  When is the deadline?  ', conversationId: 'c1');

    expect(result.valueOrNull?.isGrounded, isTrue);
    expect(repository.askedQuestions, <String>['When is the deadline?']);
    expect(repository.messages, hasLength(2));

    final question = repository.messages.first;
    expect(question.role, ChatRole.user);
    expect(question.text, 'When is the deadline?');
    expect(question.createdAt, kNow);

    final answer = repository.messages.last;
    expect(answer.role, ChatRole.assistant);
    expect(answer.text, 'The deadline is 14 August.');
    expect(answer.citations.single.pageLabel, 'Page 3');
    expect(answer.hasFailed, isFalse);
  });

  test('keeps a failed answer in the transcript, carrying the reason', () async {
    repository.answer = const Failed(
      AssistantFailure('The on-device model is not installed.'),
    );

    final result = await ask('Why?', conversationId: 'c1');

    expect(result.failureOrNull, isA<AssistantFailure>());
    expect(repository.messages, hasLength(2));
    expect(repository.messages.last.hasFailed, isTrue);
    expect(
      repository.messages.last.errorMessage,
      'The on-device model is not installed.',
    );
  });

  test('rejects a blank question without touching the transcript', () async {
    final result = await ask('   ', conversationId: 'c1');

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(repository.messages, isEmpty);
    expect(repository.askedQuestions, isEmpty);
  });

  test('rejects an over-long question', () async {
    final result = await ask(
      'x' * (AskAssistant.maxQuestionLength + 1),
      conversationId: 'c1',
    );

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(repository.messages, isEmpty);
  });

  test('forwards the document scope for "ask this document"', () async {
    await ask('What is the total?', conversationId: 'c1', documentId: 'doc-7');

    expect(repository.lastScopedDocumentId, 'doc-7');
  });

  group('AssistantAnswer', () {
    test('an answer with no citations is not grounded', () {
      const answer = AssistantAnswer(text: 'I could not find that.');

      expect(answer.isGrounded, isFalse);
      expect(answer.source, AnswerSource.retrieval);
    });

    test('citedDocumentIds de-duplicates while keeping citation order', () {
      const answer = AssistantAnswer(
        text: 'x',
        citations: <AnswerCitation>[
          AnswerCitation(
            documentId: 'b',
            documentTitle: 'B',
            pageIndex: 0,
            snippet: '',
          ),
          AnswerCitation(
            documentId: 'a',
            documentTitle: 'A',
            pageIndex: 1,
            snippet: '',
          ),
          AnswerCitation(
            documentId: 'b',
            documentTitle: 'B',
            pageIndex: 4,
            snippet: '',
          ),
        ],
      );

      expect(answer.citedDocumentIds, <String>['b', 'a']);
    });
  });
}
