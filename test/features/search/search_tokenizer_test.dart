import 'package:docuai/src/features/search/data/datasources/search_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tokenize', () {
    test('lower-cases and splits on punctuation', () {
      expect(
        SearchTokenizer.tokenize('Total Due: 42.00 EUR!'),
        <String>['total', 'due', '42', '00', 'eur'],
      );
    });

    test('keeps accented and non-ASCII letters whole', () {
      expect(
        SearchTokenizer.tokenize('Gebühr für das Café'),
        <String>['gebühr', 'für', 'das', 'café'],
        reason: 'splitting on the accent would index fragments no query types',
      );
    });

    test('drops single characters', () {
      expect(SearchTokenizer.tokenize('a bc d ef'), <String>['bc', 'ef']);
    });

    test('handles empty and whitespace-only text', () {
      expect(SearchTokenizer.tokenize(''), isEmpty);
      expect(SearchTokenizer.tokenize('   \n\t '), isEmpty);
    });

    test('treats newlines and tabs as separators', () {
      expect(
        SearchTokenizer.tokenize('invoice\nnumber\tzero'),
        <String>['invoice', 'number', 'zero'],
      );
    });
  });

  group('countTerms', () {
    test('counts repeated terms', () {
      final counts = SearchTokenizer.countTerms(
        title: '',
        body: 'rent rent deposit',
      );

      expect(counts['rent'], 2);
      expect(counts['deposit'], 1);
    });

    test('weights the title above the body', () {
      final counts = SearchTokenizer.countTerms(
        title: 'Electricity bill',
        body: 'the electricity was mentioned once',
      );

      expect(
        counts['electricity'],
        4,
        reason: 'three from the weighted title plus one from the body',
      );
      expect(counts['mentioned'], 1);
    });

    test('a document with no recognised text still has searchable terms', () {
      final counts = SearchTokenizer.countTerms(title: 'Passport', body: '');

      expect(counts['passport'], 3);
    });
  });

  group('Bm25', () {
    test('idf rises as a term gets rarer', () {
      final common = Bm25.idf(documentCount: 100, documentsContainingTerm: 90);
      final rare = Bm25.idf(documentCount: 100, documentsContainingTerm: 2);

      expect(rare, greaterThan(common));
    });

    test('idf never goes negative for a very common term', () {
      expect(
        Bm25.idf(documentCount: 10, documentsContainingTerm: 10),
        greaterThanOrEqualTo(0),
        reason: 'a negative idf can rank a match below a non-match',
      );
    });

    test('term frequency saturates rather than scaling linearly', () {
      double scoreFor(int frequency) => Bm25.termScore(
        frequency: frequency,
        documentLength: 100,
        averageDocumentLength: 100,
        idf: 1,
      );

      final one = scoreFor(1);
      final two = scoreFor(2);
      final twenty = scoreFor(20);

      expect(two, greaterThan(one));
      expect(
        twenty,
        lessThan(one * 20),
        reason: 'twenty mentions are not twenty times as relevant',
      );
    });

    test('a long document scores lower than a short one for the same hit', () {
      double scoreFor(int length) => Bm25.termScore(
        frequency: 3,
        documentLength: length,
        averageDocumentLength: 200,
        idf: 1,
      );

      expect(scoreFor(50), greaterThan(scoreFor(800)));
    });

    test('an empty corpus does not divide by zero', () {
      expect(
        Bm25.termScore(
          frequency: 1,
          documentLength: 0,
          averageDocumentLength: 0,
          idf: 1,
        ),
        isA<double>().having((value) => value.isFinite, 'isFinite', isTrue),
      );
    });
  });
}
