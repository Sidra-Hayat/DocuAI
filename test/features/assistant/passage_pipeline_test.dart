import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_ranker.dart';
import 'package:docuai/src/features/assistant/data/datasources/question_analyzer.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  Document documentWith(List<String> pageTexts, {String id = 'doc-1'}) =>
      buildDocument(
        id: id,
        title: 'Rental agreement',
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

  group('PassageExtractor', () {
    test('splits page text into sentences', () {
      final passages = PassageExtractor.extract(
        documentWith(<String>[
          'The tenant pays monthly. The deposit is two months rent. '
              'Keys are handed over on signing.',
        ]),
      );

      expect(passages, hasLength(3));
      expect(passages[1].text, 'The deposit is two months rent.');
    });

    test('treats line breaks as boundaries, since forms lack punctuation', () {
      final passages = PassageExtractor.extract(
        documentWith(<String>[
          'Account holder Jane Doe\nAmount due 42.00 EUR\nPayable by 14/08/2026',
        ]),
      );

      expect(passages, hasLength(3));
      expect(passages[1].text, 'Amount due 42.00 EUR');
    });

    test('discards fragments too short to answer anything', () {
      final passages = PassageExtractor.extract(
        documentWith(<String>['Page 3\nThe deposit is two months rent.']),
      );

      expect(passages.map((passage) => passage.text), <String>[
        'The deposit is two months rent.',
      ]);
    });

    test('splits an unpunctuated run rather than emitting a whole page', () {
      final passages = PassageExtractor.extract(
        documentWith(<String>['word ' * 200]),
      );

      expect(passages.length, greaterThan(1));
      for (final passage in passages) {
        expect(
          passage.text.length,
          lessThanOrEqualTo(PassageExtractor.maxPassageChars),
        );
      }
    });

    test('records where each passage came from', () {
      final passages = PassageExtractor.extract(
        documentWith(<String>['First page text here.', 'Second page text.']),
      );

      expect(passages.first.pageIndex, 0);
      expect(passages.last.pageIndex, 1);
      expect(passages.first.documentTitle, 'Rental agreement');
      expect(passages.first.documentId, 'doc-1');
    });

    test('skips pages with no recognised text', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.failed),
          buildPage(
            id: 'b',
            index: 1,
            text: 'Readable content on this page.',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );

      final passages = PassageExtractor.extract(document);

      expect(passages, hasLength(1));
      expect(passages.single.pageIndex, 1);
    });

    group('citationSnippet', () {
      test('widens the passage with surrounding context', () {
        // Padded well past the citation window on both sides, so the excerpt
        // is genuinely truncated and the ellipses mean something.
        final passages = PassageExtractor.extract(
          documentWith(<String>[
            '${'Preceding context. ' * 30}The deposit is two months rent. '
                '${'Following context. ' * 30}',
          ]),
        );
        final target = passages.firstWhere(
          (passage) => passage.text.contains('deposit'),
        );

        final snippet = PassageExtractor.citationSnippet(target);

        expect(snippet, contains('deposit'));
        expect(snippet, contains('Preceding'));
        expect(snippet, contains('Following'));
        expect(snippet, startsWith('…'));
        expect(snippet, endsWith('…'));
      });

      test('does not mark a snippet that reaches the page edges', () {
        final passages = PassageExtractor.extract(
          documentWith(<String>['The deposit is two months rent.']),
        );

        final snippet = PassageExtractor.citationSnippet(passages.single);

        expect(snippet, 'The deposit is two months rent.');
      });
    });
  });

  group('PassageRanker', () {
    List<RankedPassage> rankFor(String question, List<String> pageTexts) =>
        PassageRanker.rank(
          question: QuestionAnalyzer.analyze(question),
          passages: PassageExtractor.extract(documentWith(pageTexts)),
          documentPriors: const <String, double>{'doc-1': 1},
        );

    test('puts the passage containing the answer first', () {
      final ranked = rankFor('How much is the deposit?', <String>[
        'The tenant shall keep the property in good order.\n'
            'The deposit is 1,200.00 EUR payable on signing.\n'
            'Notice periods are set out in schedule two.',
      ]);

      expect(ranked.first.passage.text, contains('deposit is 1,200.00 EUR'));
    });

    test('rejects a passage matching too few of the question terms', () {
      final ranked = rankFor('deposit refund timeline', <String>[
        'The deposit is mentioned here and nothing else relevant appears.',
      ]);

      expect(
        ranked,
        isEmpty,
        reason: 'one term out of three must not look like an answer',
      );
    });

    test('a single-term question needs only that term', () {
      final ranked = rankFor('deposit', <String>[
        'The deposit is two months rent, payable before the keys are handed '
            'over to the tenant.',
      ]);

      expect(ranked, hasLength(1));
      expect(ranked.single.coverage, 1.0);
    });

    test('prefers a passage carrying a date when a date was asked for', () {
      final ranked = rankFor('When is the rent due?', <String>[
        'The rent is discussed at length in this clause about rent.\n'
            'Rent is due on 14/08/2026.',
      ]);

      expect(ranked.first.passage.text, contains('14/08/2026'));
    });

    test('prefers a passage carrying an amount when one was asked for', () {
      final ranked = rankFor('How much is the rent?', <String>[
        'The rent shall be reviewed annually as set out below.\n'
            'Rent is 950.00 EUR each month.',
      ]);

      expect(ranked.first.passage.text, contains('950.00'));
    });

    test('a stronger document lifts its passages', () {
      final passages = <Passage>[
        ...PassageExtractor.extract(
          documentWith(<String>['The deposit is two months rent.'], id: 'weak'),
        ),
        ...PassageExtractor.extract(
          documentWith(
            <String>['The deposit is two months rent.'],
            id: 'strong',
          ),
        ),
      ];

      final ranked = PassageRanker.rank(
        question: QuestionAnalyzer.analyze('deposit'),
        passages: passages,
        documentPriors: PassageRanker.priorsFrom(<String, double>{
          'weak': 1,
          'strong': 10,
        }),
      );

      expect(ranked.first.passage.documentId, 'strong');
    });

    test('an empty question ranks nothing', () {
      expect(
        PassageRanker.rank(
          question: QuestionAnalyzer.analyze('?!'),
          passages: PassageExtractor.extract(
            documentWith(<String>['Some readable content here.']),
          ),
          documentPriors: const <String, double>{},
        ),
        isEmpty,
      );
    });
  });

  group('priorsFrom', () {
    test('maps scores onto a bounded multiplier', () {
      final priors = PassageRanker.priorsFrom(<String, double>{
        'top': 8,
        'middle': 4,
        'bottom': 0,
      });

      expect(priors['top'], 1.0);
      expect(priors['middle'], closeTo(0.75, 0.001));
      expect(priors['bottom'], 0.5);
    });

    test('an unbounded BM25 score cannot dominate the ranking', () {
      final priors = PassageRanker.priorsFrom(<String, double>{
        'huge': 10000,
        'small': 1,
      });

      expect(priors.values.every((value) => value <= 1 && value >= 0.5), isTrue);
    });

    test('handles an empty or all-zero score set', () {
      expect(PassageRanker.priorsFrom(const <String, double>{}), isEmpty);
      expect(
        PassageRanker.priorsFrom(<String, double>{'a': 0, 'b': 0})['a'],
        1.0,
      );
    });
  });
}
