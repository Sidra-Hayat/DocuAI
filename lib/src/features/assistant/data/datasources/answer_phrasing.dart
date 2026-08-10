/// Turning facts into a sentence a person would read.
///
/// The line this file walks: the *numbers and words* it arranges were all read
/// off a page, and the only thing added is the grammar joining them — "two
/// dates and one amount" rather than "dates: 2, amounts: 1". Counting is not
/// interpretation, and neither is a comma.
///
/// It stops well short of describing what a document *means*. There is no
/// language model here, and a sentence claiming to summarise the significance
/// of a bill would be the one thing this assistant promises never to produce.
abstract final class AnswerPhrasing {
  /// "one date", "three amounts", "12 references".
  ///
  /// Words up to ten, digits above. Prose reads better with small numbers
  /// spelled out, and worse with large ones.
  static String count(int value, String singular, String plural) =>
      '${_number(value)} ${value == 1 ? singular : plural}';

  static const List<String> _words = <String>[
    'no',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
  ];

  static String _number(int value) =>
      value >= 0 && value < _words.length ? _words[value] : '$value';

  /// "A", "A and B", "A, B and C".
  ///
  /// No serial comma, which is the house style of every document this app is
  /// likely to hold.
  static String list(Iterable<String> items) {
    final values = items.where((item) => item.trim().isNotEmpty).toList();

    return switch (values.length) {
      0 => '',
      1 => values.single,
      _ => '${values.take(values.length - 1).join(', ')} and ${values.last}',
    };
  }

  /// A label at the start of a sentence.
  static String capitalise(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

  /// A sentence's worth of text, with any trailing full stop removed.
  ///
  /// So that quoting a line inside a sentence of our own does not produce
  /// "…supply address below..".
  static String withoutTrailingStop(String text) {
    final trimmed = text.trim();
    return trimmed.endsWith('.')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
