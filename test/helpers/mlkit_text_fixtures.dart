import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Builders for the JSON shape ML Kit's plugin decodes.
///
/// Recognition results are built through `RecognizedText.fromJson` rather than
/// by constructing the classes directly, because that is exactly what the
/// plugin does with the method channel's reply — so a fixture that parses here
/// is a reply that would parse on a device.

Map<String, dynamic> rect({
  required double left,
  required double top,
  required double right,
  required double bottom,
}) => <String, dynamic>{
  'left': left,
  'top': top,
  'right': right,
  'bottom': bottom,
};

Map<String, dynamic> element(
  String text, {
  required double left,
  required double top,
  required double right,
  required double bottom,
}) => <String, dynamic>{
  'text': text,
  'rect': rect(left: left, top: top, right: right, bottom: bottom),
  'recognizedLanguages': <String>[],
  'points': <Map<String, dynamic>>[],
  'symbols': <Map<String, dynamic>>[],
  'confidence': null,
  'angle': null,
};

/// A line. When [elements] is omitted the words in [text] are laid out across
/// the line's own box, which is what ML Kit reports for ordinary running text.
Map<String, dynamic> line(
  String text, {
  required double left,
  required double top,
  required double right,
  required double bottom,
  List<Map<String, dynamic>>? elements,
}) {
  final words = text.split(' ').where((word) => word.isNotEmpty).toList();
  final width = words.isEmpty ? 0.0 : (right - left) / words.length;

  return <String, dynamic>{
    'text': text,
    'rect': rect(left: left, top: top, right: right, bottom: bottom),
    'recognizedLanguages': <String>[],
    'points': <Map<String, dynamic>>[],
    'confidence': null,
    'angle': null,
    'elements':
        elements ??
        <Map<String, dynamic>>[
          for (var i = 0; i < words.length; i++)
            element(
              words[i],
              left: left + i * width,
              top: top,
              right: left + (i + 1) * width,
              bottom: bottom,
            ),
        ],
  };
}

/// A line with no elements — what iOS returns, and the fallback path.
Map<String, dynamic> lineWithoutElements(
  String text, {
  required double left,
  required double top,
  required double right,
  required double bottom,
}) => <String, dynamic>{
  'text': text,
  'rect': rect(left: left, top: top, right: right, bottom: bottom),
  'recognizedLanguages': <String>[],
  'points': <Map<String, dynamic>>[],
  'confidence': null,
  'angle': null,
  'elements': <Map<String, dynamic>>[],
};

Map<String, dynamic> block(List<Map<String, dynamic>> lines) {
  final boxes = lines.map((line) => line['rect'] as Map<String, dynamic>);

  return <String, dynamic>{
    'text': lines.map((line) => line['text']).join('\n'),
    'rect': rect(
      left: boxes.map((box) => box['left'] as double).reduce(_min),
      top: boxes.map((box) => box['top'] as double).reduce(_min),
      right: boxes.map((box) => box['right'] as double).reduce(_max),
      bottom: boxes.map((box) => box['bottom'] as double).reduce(_max),
    ),
    'recognizedLanguages': <String>[],
    'points': <Map<String, dynamic>>[],
    'lines': lines,
  };
}

/// The full method-channel reply.
///
/// [flatText] stands in for Android's `Text.getText()` — block texts joined by
/// newlines, which is the very output this project stopped using.
Map<String, dynamic> recognitionReply(List<Map<String, dynamic>> blocks) =>
    <String, dynamic>{
      'text': blocks.map((block) => block['text']).join('\n'),
      'blocks': blocks,
    };

RecognizedText recognizedText(List<Map<String, dynamic>> blocks) =>
    RecognizedText.fromJson(recognitionReply(blocks));

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;
