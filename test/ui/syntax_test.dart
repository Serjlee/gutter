import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/ui/diff/syntax.dart';

String plain(List<TextSpan> line) => line.map((s) => s.text).join();

void main() {
  test('languageForPath', () {
    expect(languageForPath('lib/main.dart'), 'dart');
    expect(languageForPath('a/b/Component.TSX'), 'typescript');
    expect(languageForPath('docker/Dockerfile'), 'dockerfile');
    expect(languageForPath('README'), isNull);
    expect(languageForPath('data.unknownext'), isNull);
  });

  test('splits highlighted spans back into the original lines', () {
    const code = 'void main() {\n  // hi\n  print("x");\n}\n';
    final lines = highlightLines(code, 'dart')!;
    expect(lines.map(plain).toList(), code.split('\n'));
    // Some tokens carry a style (keyword, comment, string).
    final styled = lines.expand((l) => l).where((s) => s.style?.color != null);
    expect(styled, isNotEmpty);
  });

  test('multi-line constructs keep their style on every line', () {
    const code = 'a = 1\n/* start\nmiddle\nend */\nb = 2';
    final lines = highlightLines(code, 'javascript')!;
    expect(lines, hasLength(5));
    final commentColor = lines[1].single.style!.color;
    expect(commentColor, isNotNull);
    expect(lines[2].single.style!.color, commentColor);
    expect(lines[3].first.style!.color, commentColor);
  });

  test('empty text and oversized text', () {
    expect(highlightLines('', 'dart'), [<TextSpan>[]]);
    expect(highlightLines('x' * (maxHighlightChars + 1), 'dart'), isNull);
  });
}
