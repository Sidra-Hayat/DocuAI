import 'dart:convert';
import 'dart:io';

import 'package:docuai/src/features/help/presentation/screens/help_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every string the app ships, checked for encoding damage.
///
/// This exists because it actually happened: an editing tool that read a UTF-8
/// file as Windows-1252 and wrote it back as UTF-8 turned every em dash in five
/// files into a three-character run of noise, and it reached a real phone — the
/// guide screen read `Write something yourself <noise> notes, a list, a draft`.
///
/// The damage is invisible to `flutter analyze`, invisible to every other test,
/// and easy to miss in a diff unless you already know to look. It is exactly
/// the kind of fault that needs a machine watching for it.
///
/// Scans source files rather than a curated list of strings: the corruption
/// comes from tooling touching *files*, so a file is the unit that has to be
/// checked, and a screen written next week is covered the day it is written.
void main() {
  // Built from code points rather than written literally, so this file does not
  // itself contain the sequences it is looking for — which is what made the
  // first version of this test fail against its own source.
  const damageStart = <int>[0x00C2, 0x00C3, 0x00E2]; // Â  Ã  â
  const damageFollow = <int>[
    0x20AC, // €
    0x2122, // ™
    0x0153, // œ
    0x2013, 0x2014, // – —
    0x2018, 0x2019, // ‘ ’
    0x201C, 0x201D, // “ ”
    0x2026, // …
    0x00A0, 0x00A2, 0x00B7, 0x00BD, // nbsp ¢ · ½
  ];

  String charClass(List<int> codes) =>
      '[${codes.map(String.fromCharCode).join()}]';

  /// A run that looks like UTF-8 bytes misread as Windows-1252 and re-saved.
  ///
  /// The three starters are the first character of the misreading of every
  /// multi-byte UTF-8 punctuation sequence, and no legitimate English string
  /// puts one immediately before another high character.
  final mojibake = RegExp('${charClass(damageStart)}${charClass(damageFollow)}');

  List<File> sourceFiles() => <File>[
    for (final directory in <String>['lib', 'test'])
      ...Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ...Directory('android/app/src/main/res')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.xml')),
  ];

  group('source encoding', () {
    test('every source file is valid UTF-8', () {
      final broken = <String>[
        for (final file in sourceFiles())
          if (!_decodes(file)) file.path,
      ];

      expect(broken, isEmpty, reason: 'not decodable as UTF-8: $broken');
    });

    test('no file carries double-encoded punctuation', () {
      final damaged = <String, String>{};

      for (final file in sourceFiles()) {
        final source = file.readAsStringSync();
        final match = mojibake.firstMatch(source);
        if (match == null) continue;

        // The surrounding sentence, so a failure names what to fix rather than
        // leaving somebody to hunt through the file for it.
        final from = (match.start - 40).clamp(0, source.length);
        final to = (match.end + 40).clamp(0, source.length);
        damaged[file.path] = source.substring(from, to).replaceAll('\n', ' ');
      }

      expect(
        damaged,
        isEmpty,
        reason:
            'a tool has read UTF-8 as Windows-1252 and written it back:\n'
            '${damaged.entries.map((e) => '  ${e.key}\n    ...${e.value}...').join('\n')}',
      );
    });

    test('no file starts with a byte-order mark', () {
      // Harmless to Dart, but the same tooling fault by another name, and how
      // the encoding damage above was first noticed.
      final withBom = <String>[
        for (final file in sourceFiles())
          if (_hasBom(file)) file.path,
      ];

      expect(withBom, isEmpty, reason: 'byte-order mark in: $withBom');
    });

    test('the repair restored punctuation rather than removing it', () {
      // The guide is written with em dashes. A "fix" that deleted them would
      // pass every check above and leave the sentences wrong.
      final guide = File(
        'lib/src/features/help/presentation/screens/help_screen.dart',
      ).readAsStringSync();

      expect(guide, contains(String.fromCharCode(0x2014)));
      expect(mojibake.hasMatch(guide), isFalse);
    });
  });

  group('the guide reads as it was written', () {
    testWidgets('no damaged punctuation reaches the screen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
      await tester.pumpAndSettle();

      // Scrolled end to end. The guide is a lazy `ListView`, so checking only
      // what is on screen at rest would leave four of its six sections
      // unexamined — which is how the first version of this test passed while
      // the damage was still there.
      final seen = StringBuffer();
      final scrollable = find.byType(Scrollable).first;

      for (var i = 0; i < 12; i++) {
        seen.write(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? '')
              .join(' '),
        );
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      final rendered = seen.toString();
      expect(rendered, isNotEmpty);
      expect(
        mojibake.hasMatch(rendered),
        isFalse,
        reason: 'the guide shows damaged punctuation',
      );
      expect(
        rendered,
        contains(String.fromCharCode(0x2014)),
        reason: 'the guide should still contain the em dashes it was written '
            'with — a repair that deleted them would look clean and read wrong',
      );
    });
  });
}

bool _decodes(File file) {
  try {
    utf8.decode(file.readAsBytesSync());
    return true;
  } on FormatException {
    return false;
  }
}

bool _hasBom(File file) {
  final head = file.readAsBytesSync().take(3).toList();
  return head.length == 3 &&
      head[0] == 0xEF &&
      head[1] == 0xBB &&
      head[2] == 0xBF;
}
