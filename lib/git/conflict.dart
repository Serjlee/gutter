/// Conflict markers in a file, as git leaves them:
///
/// ```
/// <<<<<<< HEAD
/// current side
/// ||||||| base          (with merge.conflictStyle diff3 / zdiff3)
/// common ancestor
/// =======
/// incoming side
/// >>>>>>> feature
/// ```
library;

enum ConflictChoice { current, incoming, both }

/// One conflict: the two sides (and the common ancestor, when git wrote
/// it). Lines keep their line endings.
class ConflictBlock {
  ConflictBlock({
    required this.current,
    required this.incoming,
    required this.currentLabel,
    required this.incomingLabel,
    required this.raw,
    this.base,
  });

  final List<String> current;
  final List<String> incoming;
  final List<String>? base;
  final String currentLabel;
  final String incomingLabel;

  /// The block as it is in the file, markers included.
  final List<String> raw;

  List<String> linesFor(ConflictChoice c) => switch (c) {
    ConflictChoice.current => current,
    ConflictChoice.incoming => incoming,
    ConflictChoice.both => [...current, ...incoming],
  };
}

/// A file's text split into plain runs of lines ([List<String>]) and
/// conflicts ([ConflictBlock]).
class ConflictedText {
  ConflictedText._(this.segments);

  final List<Object> segments;

  List<ConflictBlock> get conflicts =>
      segments.whereType<ConflictBlock>().toList();

  static final _start = RegExp(r'^<{7}(?: |\r?\n?$)');
  static final _base = RegExp(r'^\|{7}(?: |\r?\n?$)');
  static final _sep = RegExp(r'^={7}\r?\n?$');
  static final _end = RegExp(r'^>{7}(?: |\r?\n?$)');

  static String _label(String markerLine) =>
      markerLine.length > 8 ? markerLine.substring(8).trim() : '';

  /// Splits [text] into lines, each with its line ending.
  static List<String> lines(String text) {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        out.add(text.substring(start, i + 1));
        start = i + 1;
      }
    }
    if (start < text.length) out.add(text.substring(start));
    return out;
  }

  /// Whether [text] still has conflict markers.
  static bool hasMarkers(String text) {
    var inConflict = false;
    for (final l in lines(text)) {
      if (_start.hasMatch(l)) inConflict = true;
      if (inConflict && _end.hasMatch(l)) return true;
    }
    return false;
  }

  static ConflictedText parse(String text) {
    final all = lines(text);
    final segments = <Object>[];
    var plain = <String>[];
    var i = 0;
    while (i < all.length) {
      final block = _block(all, i);
      if (block == null) {
        plain.add(all[i++]);
        continue;
      }
      if (plain.isNotEmpty) segments.add(plain);
      plain = <String>[];
      segments.add(block.$1);
      i = block.$2;
    }
    if (plain.isNotEmpty) segments.add(plain);
    return ConflictedText._(segments);
  }

  /// The conflict starting at [i], and the index after it; null when the
  /// markers there don't form a complete conflict.
  static (ConflictBlock, int)? _block(List<String> all, int i) {
    if (!_start.hasMatch(all[i])) return null;
    final current = <String>[];
    List<String>? base;
    final incoming = <String>[];
    var part = 0; // 0 current, 1 base, 2 incoming
    for (var j = i + 1; j < all.length; j++) {
      final l = all[j];
      if (part == 0 && _base.hasMatch(l)) {
        base = [];
        part = 1;
      } else if (part < 2 && _sep.hasMatch(l)) {
        part = 2;
      } else if (part == 2 && _end.hasMatch(l)) {
        return (
          ConflictBlock(
            current: current,
            incoming: incoming,
            base: base,
            currentLabel: _label(all[i]),
            incomingLabel: _label(l),
            raw: all.sublist(i, j + 1),
          ),
          j + 1,
        );
      } else if (_start.hasMatch(l)) {
        return null; // nested or broken markers: leave them as text
      } else {
        (part == 0
                ? current
                : part == 1
                ? base!
                : incoming)
            .add(l);
      }
    }
    return null;
  }

  /// The text with conflict [index] (counting conflicts only) replaced by
  /// [choice]; the other conflicts keep their markers.
  String resolve(int index, ConflictChoice choice) {
    final out = StringBuffer();
    var n = 0;
    for (final s in segments) {
      if (s is ConflictBlock) {
        final lines = n++ == index ? _joinable(s.linesFor(choice)) : s.raw;
        lines.forEach(out.write);
      } else {
        (s as List<String>).forEach(out.write);
      }
    }
    return out.toString();
  }

  /// "Both" joins two sides: make sure the first ends with a line break.
  static List<String> _joinable(List<String> lines) => [
    for (var i = 0; i < lines.length; i++)
      i < lines.length - 1 && !lines[i].endsWith('\n')
          ? '${lines[i]}\n'
          : lines[i],
  ];
}
