import 'package:docuai/src/features/assistant/data/datasources/question_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terms', () {
    test('drops stopwords so coverage measures something meaningful', () {
      final analyzed = QuestionAnalyzer.analyze('When is the deadline?');

      expect(analyzed.terms, <String>['deadline']);
    });

    test('keeps order and removes duplicates', () {
      final analyzed = QuestionAnalyzer.analyze(
        'rent deposit rent agreement deposit',
      );

      expect(analyzed.terms, <String>['rent', 'deposit', 'agreement']);
    });

    test('falls back to raw tokens when every word is a stopword', () {
      final analyzed = QuestionAnalyzer.analyze('what is it');

      expect(
        analyzed.terms,
        isNotEmpty,
        reason: 'a question of common words still deserves an attempt',
      );
      expect(analyzed.isEmpty, isFalse);
    });

    test('a question with no usable characters is empty', () {
      expect(QuestionAnalyzer.analyze('?! ...').isEmpty, isTrue);
    });
  });

  group('intent', () {
    test('recognises a question about a date', () {
      for (final question in <String>[
        'When is the rent due?',
        'What is the expiry date?',
        'What is the deadline for submission?',
      ]) {
        expect(
          QuestionAnalyzer.analyze(question).intent,
          QuestionIntent.date,
          reason: question,
        );
      }
    });

    test('recognises a question about an amount', () {
      for (final question in <String>[
        'How much is the bill?',
        'What is the total?',
        'What fee did I pay?',
      ]) {
        expect(
          QuestionAnalyzer.analyze(question).intent,
          QuestionIntent.amount,
          reason: question,
        );
      }
    });

    test('anything else is general', () {
      expect(
        QuestionAnalyzer.analyze('Who signed the agreement?').intent,
        QuestionIntent.general,
      );
    });

    test('reads intent from words that are themselves stopwords', () {
      // "when" and "how" carry the intent but are filtered out of the terms,
      // so intent must be read before filtering.
      final analyzed = QuestionAnalyzer.analyze('When?');

      expect(analyzed.intent, QuestionIntent.date);
    });
  });

  group('PassageSignals', () {
    test('finds numeric and written dates', () {
      expect(PassageSignals.hasDate('Due on 14/08/2026'), isTrue);
      expect(PassageSignals.hasDate('Payable by 2026-08-14'), isTrue);
      expect(PassageSignals.hasDate('Expires 14 August 2026'), isTrue);
      expect(PassageSignals.hasDate('Aug 14, 2026'), isTrue);
    });

    test('does not treat any number as a date', () {
      expect(PassageSignals.hasDate('Reference number 4471'), isFalse);
      expect(PassageSignals.hasDate('Page 3 of 12'), isFalse);
    });

    test('finds currency amounts', () {
      expect(PassageSignals.hasAmount(r'Total: $42.00'), isTrue);
      expect(PassageSignals.hasAmount('Amount due €1,250.00'), isTrue);
      expect(PassageSignals.hasAmount('Balance 1 250,00'), isTrue);
      expect(PassageSignals.hasAmount('EUR 99'), isTrue);
      expect(PassageSignals.hasAmount('The fee is 42.50'), isTrue);
    });

    test('does not treat a bare integer as an amount', () {
      expect(
        PassageSignals.hasAmount('Page 3'),
        isFalse,
        reason: 'a page number would otherwise count as an amount everywhere',
      );
      expect(PassageSignals.hasAmount('Clause 7 applies'), isFalse);
    });

    test('satisfies only matches the intent that was asked', () {
      expect(
        PassageSignals.satisfies(QuestionIntent.date, 'Due 14/08/2026'),
        isTrue,
      );
      expect(
        PassageSignals.satisfies(QuestionIntent.amount, 'Due 14/08/2026'),
        isFalse,
      );
      expect(
        PassageSignals.satisfies(QuestionIntent.general, r'Total $42.00'),
        isFalse,
        reason: 'a general question gets no boost from either signal',
      );
    });
  });
}
