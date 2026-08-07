import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/datasources/question_analyzer.dart';
import 'package:docuai/src/features/assistant/data/datasources/synonym_index.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/usecases/suggest_questions.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

void main() {
  group('SynonymIndex', () {
    test('expansion is bidirectional within a group', () {
      expect(SynonymIndex.alternativesFor('invoice'), contains('bill'));
      expect(SynonymIndex.alternativesFor('bill'), contains('invoice'));
    });

    test('a term is never its own alternative', () {
      expect(SynonymIndex.alternativesFor('total'), isNot(contains('total')));
    });

    test('unknown words expand to nothing', () {
      expect(SynonymIndex.alternativesFor('helicopter'), isEmpty);
    });

    test('expanding a query drops the originals', () {
      final expanded = SynonymIndex.expand(<String>['total', 'due']);

      expect(expanded, contains('amount'));
      expect(expanded, contains('deadline'));
      expect(expanded, isNot(contains('total')));
      expect(expanded, isNot(contains('due')));
    });

    test('synonyms are worth less than the user\'s own wording', () {
      expect(SynonymIndex.weight, lessThan(1));
      expect(SynonymIndex.weight, greaterThan(0));
    });
  });

  group('question understanding', () {
    test('expands contractions so no stray letter survives', () {
      final analyzed = QuestionAnalyzer.analyze("What's the total?");

      expect(analyzed.terms, isNot(contains('s')));
      expect(analyzed.terms, contains('total'));
    });

    test('carries synonyms alongside the original terms', () {
      final analyzed = QuestionAnalyzer.analyze('What is the invoice total?');

      expect(analyzed.terms, contains('invoice'));
      expect(analyzed.synonyms, contains('bill'));
      expect(
        analyzed.synonyms,
        isNot(contains('invoice')),
        reason: 'exact and synonym matches must stay distinguishable',
      );
    });

    test('treats a quoted run as a phrase', () {
      final analyzed = QuestionAnalyzer.analyze(
        'Where does it say "notice period"?',
      );

      expect(analyzed.phrases, <String>['notice period']);
    });

    test('recognises the newer intents', () {
      expect(
        QuestionAnalyzer.analyze('What is the phone number for support?').intent,
        QuestionIntent.contact,
      );
      expect(
        QuestionAnalyzer.analyze('What is my account reference?').intent,
        QuestionIntent.identifier,
      );
      expect(
        QuestionAnalyzer.analyze('Where is the property?').intent,
        QuestionIntent.place,
      );
    });

    test('the more specific reading wins when a question qualifies twice', () {
      expect(
        QuestionAnalyzer.analyze('How much is the deposit due?').intent,
        QuestionIntent.amount,
        reason: '"how much" is the question; "due" is incidental',
      );
    });
  });

  group('PassageSignals additions', () {
    test('finds contact details', () {
      expect(PassageSignals.hasContact('Email us at help@example.com'), isTrue);
      expect(PassageSignals.hasContact('Call +44 20 7946 0958'), isTrue);
      expect(PassageSignals.hasContact('No contact here'), isFalse);
    });

    test('finds reference-shaped identifiers but not plain quantities', () {
      expect(PassageSignals.hasIdentifier('Account AB77219043'), isTrue);
      expect(PassageSignals.hasIdentifier('Page 3 of 12'), isFalse);
    });

    test('finds a proper name', () {
      expect(PassageSignals.hasProperName('Signed by Jane Doe'), isTrue);
      expect(PassageSignals.hasProperName('signed by the tenant'), isFalse);
    });
  });

  group('RecentQuestions', () {
    test('returns the newest first', () {
      expect(
        RecentQuestions.from(<String>['first', 'second', 'third']),
        <String>['third', 'second', 'first'],
      );
    });

    test('collapses repeats to their most recent occurrence', () {
      expect(
        RecentQuestions.from(<String>['total', 'due', 'Total']),
        <String>['Total', 'due'],
      );
    });

    test('caps the list', () {
      final many = List<String>.generate(20, (i) => 'question $i');

      expect(RecentQuestions.from(many), hasLength(RecentQuestions.max));
    });

    test('ignores blanks', () {
      expect(RecentQuestions.from(<String>['   ', 'real']), <String>['real']);
    });
  });

  group('retrieval', () {
    late Directory tempDir;
    late Box<ChatMessageModel> box;
    late FakeSearchRepository search;
    late FakeDocumentRepository documents;
    late RetrievalAssistantRepository repository;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_assist_up');
      Hive.init(p.join(tempDir.path, 'hive'));
      Hive.registerAdapters();
    });

    setUp(() async {
      box = await Hive.openBox<ChatMessageModel>(
        'chat_${DateTime.now().microsecondsSinceEpoch}',
      );
      search = FakeSearchRepository();
      documents = FakeDocumentRepository();
      repository = RetrievalAssistantRepository(
        search: search,
        documents: documents,
        history: ChatHistoryLocalDataSource(box),
      );
    });

    tearDown(() async {
      await box.deleteFromDisk();
      documents.dispose();
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Document documentWith({
      required String id,
      required String title,
      required List<String> pageTexts,
    }) => buildDocument(
      id: id,
      title: title,
      pages: <DocumentPage>[
        for (var i = 0; i < pageTexts.length; i++)
          buildPage(
            id: '$id-p$i',
            index: i,
            text: pageTexts[i],
            ocrStatus: OcrStatus.completed,
          ),
      ],
    );

    void library(List<Document> docs) {
      for (final document in docs) {
        documents.seed(document);
      }
      search.results = <SearchHit>[
        for (final document in docs)
          SearchHit(document: document, score: 5 - docs.indexOf(document).toDouble()),
      ];
    }

    test('a synonym finds the page the exact word would have missed', () async {
      library(<Document>[
        documentWith(
          id: 'bill',
          title: 'Water bill',
          pageTexts: <String>[
            'The total payable for this quarter is 84.20 EUR.',
          ],
        ),
      ]);

      // "amount" never appears on the page; "total" does, and they are the
      // same thing to anyone reading a bill.
      final answer = (await repository.ask('What amount is payable?'))
          .valueOrNull!;

      expect(answer.isGrounded, isTrue);
      expect(answer.text, contains('84.20'));
    });

    test('a quoted phrase excludes passages that lack it', () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Lease',
          pageTexts: <String>[
            'The notice period is one month.\n'
                'Notice must be given in writing.',
          ],
        ),
      ]);

      final answer = (await repository.ask('What is the "notice period"?'))
          .valueOrNull!;

      expect(answer.text, contains('notice period'));
    });

    test('a question with nothing to search for says so', () async {
      library(<Document>[
        documentWith(id: 'a', title: 'A', pageTexts: <String>['content']),
      ]);

      final answer = (await repository.ask('?!  ...')).valueOrNull!;

      expect(answer.kind, AnswerKind.unclearQuestion);
      expect(answer.text, RetrievalAssistantRepository.unclearMessage);
    });

    group('confidence', () {
      test('full coverage plus the right shape is a strong match', () async {
        library(<Document>[
          documentWith(
            id: 'bill',
            title: 'Bill',
            pageTexts: <String>['The deposit is 1,200.00 EUR on signing.'],
          ),
        ]);

        final answer = (await repository.ask('How much is the deposit?'))
            .valueOrNull!;

        expect(answer.confidence, AnswerConfidence.strong);
      });

      test('coverage without the right shape is only partial', () async {
        library(<Document>[
          documentWith(
            id: 'lease',
            title: 'Lease',
            pageTexts: <String>[
              'The deposit is described in the schedule attached hereto.',
            ],
          ),
        ]);

        final answer = (await repository.ask('How much is the deposit?'))
            .valueOrNull!;

        expect(answer.confidence, AnswerConfidence.partial);
      });

      test('a fallback carries no confidence at all', () async {
        library(<Document>[
          documentWith(id: 'a', title: 'A', pageTexts: <String>['content']),
        ]);

        final answer = (await repository.ask('helicopter rotor')).valueOrNull!;

        expect(answer.confidence, isNull);
      });
    });

    group('citations', () {
      test('record which terms matched and how relevant each was', () async {
        library(<Document>[
          documentWith(
            id: 'lease',
            title: 'Lease',
            pageTexts: <String>['The deposit is 1,200.00 EUR on signing.'],
          ),
        ]);

        final citation = (await repository.ask('deposit amount'))
            .valueOrNull!
            .citations
            .first;

        expect(citation.matchedTerms, contains('deposit'));
        expect(citation.relevance, 1.0, reason: 'the best passage sets the bar');
      });

      test('group by document across several sources', () async {
        library(<Document>[
          documentWith(
            id: 'lease',
            title: 'Lease',
            pageTexts: <String>[
              'The deposit is 1,200.00 EUR on signing.',
              'The deposit is refundable within 30 days.',
            ],
          ),
          documentWith(
            id: 'receipt',
            title: 'Receipt',
            pageTexts: <String>['Deposit received, thank you.'],
          ),
        ]);

        final answer = (await repository.ask('deposit')).valueOrNull!;

        expect(answer.spansMultipleDocuments, isTrue);
        expect(answer.citationsByDocument.keys, containsAll(<String>['lease', 'receipt']));
      });

      test('report how many documents were read', () async {
        library(<Document>[
          documentWith(id: 'a', title: 'A', pageTexts: <String>['deposit one']),
          documentWith(id: 'b', title: 'B', pageTexts: <String>['deposit two']),
        ]);

        final answer = (await repository.ask('deposit')).valueOrNull!;

        expect(answer.documentsSearched, 2);
      });
    });

    group('suggested questions', () {
      test('asks about what the pages demonstrably contain', () async {
        documents
          ..seed(
            documentWith(
              id: 'bill',
              title: 'Water bill',
              pageTexts: <String>['Total due 84.20 EUR'],
            ),
          )
          ..seed(
            documentWith(
              id: 'lease',
              title: 'Lease',
              pageTexts: <String>['Expires 14 August 2026'],
            ),
          );

        final suggestions = (await repository.suggestedQuestions()).valueOrNull!;

        expect(suggestions, contains('How much is the Water bill?'));
        expect(suggestions, contains('When is the Lease due?'));
      });

      test('suggests nothing when no document has been read', () async {
        documents.seed(
          buildDocument(pages: <DocumentPage>[buildPage()]),
        );

        expect((await repository.suggestedQuestions()).valueOrNull, isEmpty);
      });

      test('suggests nothing for an empty library', () async {
        expect((await repository.suggestedQuestions()).valueOrNull, isEmpty);
      });
    });
  });
}
