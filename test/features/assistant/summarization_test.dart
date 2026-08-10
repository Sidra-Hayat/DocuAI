import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_summarizer.dart';
import 'package:docuai/src/features/assistant/data/datasources/question_analyzer.dart';
import 'package:docuai/src/features/assistant/data/datasources/shape_finder.dart';
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

/// Summarising a document, and listing what is on it.
///
/// Both are requests the term-coverage ranker cannot serve: one names nothing
/// the pages contain, the other asks for a shape rather than a word. These
/// tests hold the line that matters most — that neither invents anything. Every
/// line of a summary has to be a sentence that is actually on the page, and
/// every listed value has to be readable off it.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_summary');
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
    if (box.isOpen) await box.deleteFromDisk();
    documents.dispose();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the box file; the OS reclaims it.
    }
  });

  // A scan of the kind of document people actually put through this app.
  const billPage1 = '''
Northwind Utilities
Electricity statement for the supply address below.
Account number: NW-4471902
Invoice date: 12/03/2026
Payment due: 05/04/2026
Supply address: 14 Bridge Street, Kirkwall
Account holder: Aisha Rahman
Total amount due: £248.60
''';

  const billPage2 = '''
Your electricity use this quarter was 1,240 kWh.
Standing charge for the quarter: £54.20
Questions about this statement can be sent to billing@northwind.example.
Payment may be made by direct debit or bank transfer.
''';

  Document bill({String id = 'bill', String title = 'Electricity bill'}) =>
      buildDocument(
        id: id,
        title: title,
        pages: <DocumentPage>[
          buildPage(
            id: '$id-p0',
            index: 0,
            text: billPage1,
            ocrStatus: OcrStatus.completed,
          ),
          buildPage(
            id: '$id-p1',
            index: 1,
            text: billPage2,
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );

  /// The bullet lines of an answer, without their markers.
  List<String> bulletsOf(AssistantAnswer answer) => answer.text
      .split('\n')
      .where((line) => line.startsWith('• '))
      .map((line) => line.substring(2))
      .toList(growable: false);

  group('reading what was asked for', () {
    ({QuestionMode mode, QuestionIntent intent}) read(String question) {
      final analyzed = QuestionAnalyzer.analyze(question);
      return (mode: analyzed.mode, intent: analyzed.intent);
    }

    test('a summary is recognised however it is spelled or phrased', () {
      for (final question in <String>[
        'Summarise this document',
        'Summarize this document.',
        'summary please',
        'give me an overview',
        'what are the key points',
        'tldr',
      ]) {
        expect(
          read(question).mode,
          QuestionMode.summary,
          reason: '"$question" asks for a summary',
        );
      }
    });

    test('a request to list a shape is recognised', () {
      expect(read('Find important dates'), (
        mode: QuestionMode.find,
        intent: QuestionIntent.date,
      ));
      expect(read('Find names'), (
        mode: QuestionMode.find,
        intent: QuestionIntent.person,
      ));
      expect(read('Find amounts'), (
        mode: QuestionMode.find,
        intent: QuestionIntent.amount,
      ));
      expect(read('list all reference numbers').mode, QuestionMode.find);
    });

    test('a question that narrows to one instance stays a question', () {
      // The distinction that matters: "find the amount on the electricity
      // bill" wants an answer, not every figure on the page.
      expect(read('Find the amount on the electricity bill').mode,
          QuestionMode.answer);
      expect(read('How much is the deposit?').mode, QuestionMode.answer);
      expect(
        read('When is it due?').mode,
        QuestionMode.answer,
        reason: 'no enumeration cue — they want the due date, not every date',
      );
      expect(
        read('find the landlord address').mode,
        QuestionMode.answer,
        reason: 'a place has no shape on the page to enumerate',
      );
    });

    test('naming a document is kept apart from the words that request one', () {
      final analyzed = QuestionAnalyzer.analyze(
        'Summarise the tenancy agreement',
      );

      expect(analyzed.mode, QuestionMode.summary);
      expect(analyzed.subjectTerms, <String>['tenancy', 'agreement']);
    });

    test('referring to the document in front of you names nothing', () {
      expect(
        QuestionAnalyzer.analyze('Summarise this document').subjectTerms,
        isEmpty,
        reason: 'the only way to know a document was never identified',
      );
    });
  });

  group('reading values off the page', () {
    test('an amount is extracted whole, not truncated at the first digit', () {
      expect(
        PassageSignals.matches(QuestionIntent.amount, 'Total due: £248.60'),
        <String>['£248.60'],
      );
      expect(
        PassageSignals.matches(QuestionIntent.amount, 'Balance 1,240.00 EUR'),
        contains('1,240.00'),
      );
    });

    test('a written date keeps its year', () {
      expect(
        PassageSignals.matches(QuestionIntent.date, 'Signed on 12 March 2026'),
        <String>['12 March 2026'],
      );
    });

    test('column headings are not reported as people', () {
      // Two capitalised words is how a name reads — and also how "Total
      // Amount" and "Account Number" read. Without this the assistant reports
      // a utility bill as being full of people.
      expect(
        PassageSignals.properNames('Total Amount Due Account Number'),
        isEmpty,
      );
      expect(
        PassageSignals.properNames('Signed by Aisha Rahman'),
        <String>['Aisha Rahman'],
      );
    });
  });

  group('summarising', () {
    test('every line is a sentence that is actually on the page', () async {
      documents.seed(bill());

      final answered = await repository.ask(
        DocumentQuestions.summarise,
        documentId: 'bill',
      );
      final answer = (answered as Success<AssistantAnswer>).value;

      expect(answer.kind, AnswerKind.summary);
      final bullets = bulletsOf(answer);
      expect(bullets, isNotEmpty);

      // The whole claim of an offline summariser: nothing was written, only
      // chosen. Whitespace is normalised on the way out, so compare that way.
      final pageText = '$billPage1\n$billPage2'.replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      for (final bullet in bullets) {
        expect(
          pageText,
          contains(bullet),
          reason: 'a summary line the document does not contain was invented',
        );
      }
    });

    test('lines read in the order the document states them', () async {
      documents.seed(bill());

      final answer =
          (await repository.ask(
                DocumentQuestions.summarise,
                documentId: 'bill',
              )
              as Success<AssistantAnswer>)
          .value;

      final flat = '$billPage1\n$billPage2'.replaceAll(RegExp(r'\s+'), ' ');
      final positions = bulletsOf(
        answer,
      ).map(flat.indexOf).toList(growable: false);

      expect(
        positions,
        orderedEquals(List<int>.from(positions)..sort()),
        reason: 'ordered by score, a summary reads as arbitrary',
      );
    });

    test('it cites the pages it quoted, once per page', () async {
      documents.seed(bill());

      final answer =
          (await repository.ask(
                DocumentQuestions.summarise,
                documentId: 'bill',
              )
              as Success<AssistantAnswer>)
          .value;

      expect(answer.isGrounded, isTrue);
      expect(answer.citations.every((c) => c.documentId == 'bill'), isTrue);
      expect(
        answer.citations.map((c) => c.pageIndex).toSet(),
        hasLength(answer.citations.length),
        reason: 'three sentences from page one are one place to look',
      );
      expect(
        answer.confidence,
        isNull,
        reason: 'a summary answers no question, so it covers none of one',
      );
    });

    test('a restated sentence is not summarised twice', () {
      // Scans repeat themselves — a total in the header, the table and the
      // footer. Three phrasings of one fact is not a summary.
      const repeated = 'The total amount payable for this quarter is 248.60.';
      final document = buildDocument(
        id: 'r',
        title: 'Repeats',
        pages: <DocumentPage>[
          buildPage(
            id: 'r-p0',
            index: 0,
            ocrStatus: OcrStatus.completed,
            text:
                '$repeated\n'
                '$repeated\n'
                'The meter reading was taken on 12/03/2026 by the supplier.\n',
          ),
        ],
      );

      final sentences = PassageSummarizer.summarize(
        PassageExtractor.extract(document),
      );

      expect(sentences, hasLength(2));
    });

    test('a document is never about a number', () {
      // A figure tokenises into digits that occur once, which is the profile
      // of a maximally significant term — so left in, they bury the words and
      // two lines saying entirely different things score the same.
      documents.seed(bill());

      final sentences = PassageSummarizer.summarize(
        PassageExtractor.extract(bill()),
      );

      for (final sentence in sentences) {
        expect(
          sentence.highlights.where(RegExp(r'^\d+$').hasMatch),
          isEmpty,
          reason: 'a bare number explains nothing about why a line was picked',
        );
      }
    });

    test('it stops at a readable number of sentences', () {
      final document = buildDocument(
        id: 'long',
        title: 'Long',
        pages: <DocumentPage>[
          buildPage(
            id: 'long-p0',
            index: 0,
            ocrStatus: OcrStatus.completed,
            text: List<String>.generate(
              40,
              (i) => 'Clause $i sets out the obligations of party number $i '
                  'under the terms agreed on 0$i/03/2026 for the sum stated.',
            ).join('\n'),
          ),
        ],
      );

      expect(
        PassageSummarizer.summarize(PassageExtractor.extract(document)).length,
        lessThanOrEqualTo(PassageSummarizer.maxSentences),
      );
    });

    test('a document whose text is not recognised says so', () async {
      documents.seed(
        buildDocument(
          id: 'blank',
          title: 'Unread',
          pages: <DocumentPage>[buildPage(id: 'blank-p0', index: 0)],
        ),
      );

      final answer =
          (await repository.ask(
                DocumentQuestions.summarise,
                documentId: 'blank',
              )
              as Success<AssistantAnswer>)
          .value;

      expect(answer.kind, AnswerKind.noRecognisedText);
      expect(answer.citations, isEmpty);
    });
  });

  group('summarising without a document open', () {
    test('naming one in the question is enough', () async {
      final lease = bill(id: 'lease', title: 'Tenancy agreement');
      documents.seed(lease);
      search.results = <SearchHit>[SearchHit(document: lease, score: 9)];

      final answer =
          (await repository.ask('Summarise the tenancy agreement')
              as Success<AssistantAnswer>)
          .value;

      expect(answer.kind, AnswerKind.summary);
      expect(answer.citations.first.documentId, 'lease');
    });

    test('naming none asks for one rather than guessing', () async {
      documents
        ..seed(bill(id: 'a', title: 'One'))
        ..seed(bill(id: 'b', title: 'Two'));

      final answer =
          (await repository.ask('Summarise this document')
              as Success<AssistantAnswer>)
          .value;

      expect(answer.kind, AnswerKind.needsDocument);
      expect(
        answer.citations,
        isEmpty,
        reason: 'summarising an arbitrary document would be worse than asking',
      );
    });

    test('naming one that does not exist says so', () async {
      final answer =
          (await repository.ask('Summarise the mortgage offer')
              as Success<AssistantAnswer>)
          .value;

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, contains('mortgage'));
    });
  });

  group('listing what is on the page', () {
    Future<AssistantAnswer> askBill(String question) async {
      documents.seed(bill());
      return (await repository.ask(question, documentId: 'bill')
              as Success<AssistantAnswer>)
          .value;
    }

    test('every date, in the order the document states them', () async {
      final answer = await askBill(DocumentQuestions.dates);

      expect(answer.kind, AnswerKind.extraction);
      expect(bulletsOf(answer), <String>['12/03/2026', '05/04/2026']);
      expect(answer.text, startsWith('I found two dates'));
    });

    test('every amount, whole', () async {
      final answer = await askBill(DocumentQuestions.amounts);

      expect(bulletsOf(answer), containsAll(<String>['£248.60', '£54.20']));
      expect(
        bulletsOf(answer),
        isNot(contains('£2')),
        reason: 'a truncated figure is a wrong figure',
      );
    });

    test('names, without the column headings', () async {
      final answer = await askBill(DocumentQuestions.names);

      expect(bulletsOf(answer), contains('Aisha Rahman'));
      expect(
        bulletsOf(answer).where((name) => name.contains('Total')),
        isEmpty,
      );
      expect(
        answer.confidence,
        AnswerConfidence.partial,
        reason: 'capitalisation is a convention, not a fact about the page',
      );
    });

    test('an amount is a fact, so it is reported as one', () async {
      expect(
        (await askBill(DocumentQuestions.amounts)).confidence,
        AnswerConfidence.strong,
      );
    });

    test('the listing cites where it read', () async {
      final answer = await askBill(DocumentQuestions.dates);

      expect(answer.isGrounded, isTrue);
      expect(answer.citations.first.matchedTerms, contains('12/03/2026'));
    });

    test('a shape the document does not carry is admitted, not faked', () async {
      documents.seed(
        buildDocument(
          id: 'prose',
          title: 'Letter',
          pages: <DocumentPage>[
            buildPage(
              id: 'prose-p0',
              index: 0,
              ocrStatus: OcrStatus.completed,
              text: 'Thank you for your enquiry about the tenancy.',
            ),
          ],
        ),
      );

      final answer =
          (await repository.ask(
                DocumentQuestions.dates,
                documentId: 'prose',
              )
              as Success<AssistantAnswer>)
          .value;

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, contains('dates'));
      expect(answer.citations, isEmpty);
    });

    test('the same value stated twice is listed once', () {
      final document = buildDocument(
        id: 'dup',
        title: 'Duplicated',
        pages: <DocumentPage>[
          buildPage(
            id: 'dup-p0',
            index: 0,
            ocrStatus: OcrStatus.completed,
            text:
                'Total due 12/03/2026 as shown.\n'
                'Please pay by 12/03/2026 to avoid a charge.\n',
          ),
        ],
      );

      final found = ShapeFinder.find(
        QuestionIntent.date,
        PassageExtractor.extract(document),
      );

      expect(found.map((f) => f.value), <String>['12/03/2026']);
    });
  });

  group('what a document offers to be asked', () {
    test('only the shapes its pages actually carry', () async {
      documents.seed(bill());

      final suggestions =
          (await repository.suggestedQuestions(documentId: 'bill')
              as Success<List<String>>)
          .value;

      expect(suggestions.first, DocumentQuestions.summarise);
      expect(suggestions, contains(DocumentQuestions.dates));
      expect(suggestions, contains(DocumentQuestions.amounts));
    });

    test('nothing is offered that would come back empty', () async {
      documents.seed(
        buildDocument(
          id: 'prose',
          title: 'Letter',
          pages: <DocumentPage>[
            buildPage(
              id: 'prose-p0',
              index: 0,
              ocrStatus: OcrStatus.completed,
              text: 'Thank you for your enquiry about the tenancy.',
            ),
          ],
        ),
      );

      final suggestions =
          (await repository.suggestedQuestions(documentId: 'prose')
              as Success<List<String>>)
          .value;

      expect(suggestions, <String>[DocumentQuestions.summarise]);
    });

    test('an unread document offers nothing', () async {
      documents.seed(
        buildDocument(
          id: 'blank',
          title: 'Unread',
          pages: <DocumentPage>[buildPage(id: 'blank-p0', index: 0)],
        ),
      );

      expect(
        (await repository.suggestedQuestions(documentId: 'blank')
                as Success<List<String>>)
            .value,
        isEmpty,
      );
    });

    test('the library-wide offer still names documents', () async {
      documents.seed(bill());

      final suggestions =
          (await repository.suggestedQuestions() as Success<List<String>>)
          .value;

      expect(suggestions.single, contains('Electricity bill'));
    });
  });
}
