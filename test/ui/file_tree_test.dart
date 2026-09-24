import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/ui/details/file_tree.dart';

String describe(List<FileTreeRow<String>> rows) => rows
    .map(
      (r) =>
          '${'  ' * r.depth}${r.isDir ? '${r.label}/ (${r.fileCount})' : r.label}',
    )
    .join('\n');

void main() {
  const paths = [
    'README.md',
    'lib/main.dart',
    'lib/ui/app.dart',
    'lib/ui/widgets/button.dart',
    'lib/ui/widgets/Card.dart',
    'src/deep/nested/only/file.c',
    'a.txt',
    'Makefile',
  ];

  test('folders first, sorted, with counts and compacted chains', () {
    final rows = flattenFileTree(paths, (p) => p);
    expect(describe(rows), '''
lib/ (4)
  ui/ (3)
    widgets/ (2)
      button.dart
      Card.dart
    app.dart
  main.dart
src/deep/nested/only/ (1)
  file.c
a.txt
Makefile
README.md''');
    final file = rows.firstWhere((r) => r.label == 'file.c');
    expect(file.path, 'src/deep/nested/only/file.c');
    expect(file.item, 'src/deep/nested/only/file.c');
    expect(rows.first.path, 'lib');
  });

  test('collapsed folders hide their contents', () {
    final rows = flattenFileTree(paths, (p) => p, collapsed: {'lib/ui'});
    expect(describe(rows), '''
lib/ (4)
  ui/ (3)
  main.dart
src/deep/nested/only/ (1)
  file.c
a.txt
Makefile
README.md''');
    expect(rows[1].collapsed, isTrue);
  });

  test('flat lists and empty input', () {
    expect(describe(flattenFileTree(['b', 'a'], (p) => p)), 'a\nb');
    expect(flattenFileTree(<String>[], (p) => p), isEmpty);
  });

  test('itemsUnder matches whole folder names only', () {
    final items = ['lib/a.dart', 'lib/ui/b.dart', 'library/c.dart', 'lib'];
    expect(itemsUnder(items, (p) => p, 'lib'), ['lib/a.dart', 'lib/ui/b.dart']);
  });
}
