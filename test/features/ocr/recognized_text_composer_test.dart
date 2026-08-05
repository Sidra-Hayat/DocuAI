import 'package:docuai/src/features/ocr/data/datasources/recognized_text_composer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/mlkit_text_fixtures.dart';

void main() {
  group('the defect this fixes', () {
    test('joins fragments ML Kit split into separate blocks on one row', () {
      // Exactly what a device returns for a bill heading: two words, each its
      // own block, sitting side by side on the same baseline.
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Electricity', left: 40, top: 100, right: 180, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('Bill', left: 190, top: 101, right: 250, bottom: 131),
        ]),
        // Kept on the next line rather than after a section gap, so this test
        // is about the joining alone; spacing has its own group below.
        block(<Map<String, dynamic>>[
          line('Amount:', left: 40, top: 142, right: 140, bottom: 170),
        ]),
        block(<Map<String, dynamic>>[
          line('5000', left: 300, top: 143, right: 380, bottom: 171),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'Electricity Bill\nAmount: 5000',
      );
    });

    test('the flat ML Kit string is the broken output being replaced', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Electricity', left: 40, top: 100, right: 180, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('Bill', left: 190, top: 101, right: 250, bottom: 131),
        ]),
      ]);

      expect(
        recognized.text,
        'Electricity\nBill',
        reason: 'documents why RecognizedText.text is no longer used',
      );
      expect(RecognizedTextComposer.compose(recognized), 'Electricity Bill');
    });
  });

  group('row grouping', () {
    test('keeps text on different rows on different lines', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('First row', left: 40, top: 100, right: 200, bottom: 130),
          line('Second row', left: 40, top: 140, right: 200, bottom: 170),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'First row\nSecond row',
      );
    });

    test('orders a row left to right regardless of block order', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('third', left: 300, top: 100, right: 360, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('first', left: 40, top: 100, right: 100, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('second', left: 150, top: 100, right: 220, bottom: 130),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'first second third',
      );
    });

    test('tolerates the baseline wobble a real scan has', () {
      // Same visual row, a few pixels apart vertically — perspective correction
      // never lands two fragments on exactly the same y.
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Account', left: 40, top: 100, right: 140, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('holder', left: 150, top: 104, right: 230, bottom: 134),
        ]),
      ]);

      expect(RecognizedTextComposer.compose(recognized), 'Account holder');
    });

    test('does not pull a following line up into a tall heading', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('HEADING', left: 40, top: 100, right: 300, bottom: 160),
        ]),
        block(<Map<String, dynamic>>[
          line('body text', left: 40, top: 170, right: 250, bottom: 192),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        contains('HEADING\n'),
      );
      expect(
        RecognizedTextComposer.compose(recognized),
        isNot('HEADING body text'),
      );
    });
  });

  group('section breaks', () {
    test('a large vertical gap becomes a blank line', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Invoice header', left: 40, top: 100, right: 300, bottom: 128),
        ]),
        block(<Map<String, dynamic>>[
          line('Line one', left: 40, top: 300, right: 300, bottom: 328),
          line('Line two', left: 40, top: 334, right: 300, bottom: 362),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'Invoice header\n\nLine one\nLine two',
      );
    });

    test('ordinary line spacing does not become a blank line', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('One', left: 40, top: 100, right: 200, bottom: 128),
          line('Two', left: 40, top: 134, right: 200, bottom: 162),
          line('Three', left: 40, top: 168, right: 200, bottom: 196),
        ]),
      ]);

      expect(RecognizedTextComposer.compose(recognized), 'One\nTwo\nThree');
    });
  });

  group('element hierarchy', () {
    test('rebuilds a line from its elements in reading order', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line(
            'ignored',
            left: 40,
            top: 100,
            right: 300,
            bottom: 130,
            elements: <Map<String, dynamic>>[
              element('due', left: 160, top: 100, right: 210, bottom: 130),
              element('Total', left: 40, top: 100, right: 150, bottom: 130),
              element('42.00', left: 220, top: 100, right: 300, bottom: 130),
            ],
          ),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'Total due 42.00',
        reason: 'element order is authoritative, not the line string',
      );
    });

    test('falls back to the line text when there are no elements', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          lineWithoutElements(
            'Payable on receipt',
            left: 40,
            top: 100,
            right: 300,
            bottom: 130,
          ),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'Payable on receipt',
      );
    });
  });

  group('never inventing content', () {
    test('joins with a single space and adds no punctuation', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Amount', left: 40, top: 100, right: 140, bottom: 130),
        ]),
        block(<Map<String, dynamic>>[
          line('5000', left: 400, top: 100, right: 470, bottom: 130),
        ]),
      ]);

      expect(
        RecognizedTextComposer.compose(recognized),
        'Amount 5000',
        reason: 'a wide column gap must not become an invented colon — the '
            'assistant quotes this text verbatim',
      );
    });

    test('collapses whitespace inside a fragment', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          lineWithoutElements(
            '  Spaced   out  ',
            left: 40,
            top: 100,
            right: 300,
            bottom: 130,
          ),
        ]),
      ]);

      expect(RecognizedTextComposer.compose(recognized), 'Spaced out');
    });
  });

  group('degenerate input', () {
    test('an empty result composes to an empty string', () {
      expect(RecognizedTextComposer.compose(recognizedText(<Map<String, dynamic>>[])), '');
    });

    test('falls back to the flat text when no line carries geometry', () {
      // A block with no lines at all: nothing to lay out, but the flat string
      // is still better than returning nothing.
      final recognized = recognizedText(<Map<String, dynamic>>[
        <String, dynamic>{
          'text': 'Salvageable text',
          'rect': rect(left: 0, top: 0, right: 0, bottom: 0),
          'recognizedLanguages': <String>[],
          'points': <Map<String, dynamic>>[],
          'lines': <Map<String, dynamic>>[],
        },
      ]);

      expect(RecognizedTextComposer.compose(recognized), 'Salvageable text');
    });

    test('drops blank lines rather than emitting empty rows', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          lineWithoutElements('   ', left: 40, top: 100, right: 300, bottom: 130),
          lineWithoutElements('Real', left: 40, top: 140, right: 300, bottom: 170),
        ]),
      ]);

      expect(RecognizedTextComposer.compose(recognized), 'Real');
    });

    test('survives zero-height boxes without dividing by zero', () {
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('One', left: 40, top: 100, right: 200, bottom: 100),
          line('Two', left: 40, top: 140, right: 200, bottom: 140),
        ]),
      ]);

      final composed = RecognizedTextComposer.compose(recognized);

      expect(composed, contains('One'));
      expect(composed, contains('Two'));
    });
  });

  group('a whole page', () {
    test('reconstructs a bill the way it was printed', () {
      // Every fragment its own block, which is what the device actually
      // returned when this defect was reported.
      final recognized = recognizedText(<Map<String, dynamic>>[
        block(<Map<String, dynamic>>[
          line('Electricity', left: 40, top: 60, right: 190, bottom: 96),
        ]),
        block(<Map<String, dynamic>>[
          line('Bill', left: 200, top: 61, right: 260, bottom: 97),
        ]),
        block(<Map<String, dynamic>>[
          line('Account', left: 40, top: 200, right: 130, bottom: 226),
        ]),
        block(<Map<String, dynamic>>[
          line('holder:', left: 138, top: 200, right: 210, bottom: 226),
        ]),
        block(<Map<String, dynamic>>[
          line('Jane Doe', left: 300, top: 201, right: 420, bottom: 227),
        ]),
        block(<Map<String, dynamic>>[
          line('Amount:', left: 40, top: 240, right: 140, bottom: 266),
        ]),
        block(<Map<String, dynamic>>[
          line('5000', left: 300, top: 241, right: 370, bottom: 267),
        ]),
        block(<Map<String, dynamic>>[
          line('Due', left: 40, top: 280, right: 90, bottom: 306),
        ]),
        block(<Map<String, dynamic>>[
          line('date:', left: 98, top: 280, right: 160, bottom: 306),
        ]),
        block(<Map<String, dynamic>>[
          line('14/08/2026', left: 300, top: 281, right: 430, bottom: 307),
        ]),
      ]);

      expect(RecognizedTextComposer.compose(recognized), '''
Electricity Bill

Account holder: Jane Doe
Amount: 5000
Due date: 14/08/2026''');
    });
  });
}
