import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';

void main() {
  test('columns give way to the message, the age last', () {
    // Refs 190, author 140, age 64, sha 70; a 100 px graph; 200 px kept
    // for the message.
    final cols = GraphColumns(const {});
    String fit(double width) {
      final f = cols.fit(width, 100);
      return [
        'refs ${f.refs.round()}',
        if (f.author != null) 'author',
        if (f.age != null) 'age',
        if (f.sha != null) 'sha',
      ].join(', ');
    }

    expect(fit(800), 'refs 190, author, age, sha');
    expect(fit(700), 'refs 190, author, age');
    // The refs shrink before the author goes, and again before the age.
    expect(fit(620), 'refs 116, author, age');
    expect(fit(560), 'refs 110, age');
    expect(fit(450), 'refs 86, age');
    expect(fit(380), 'refs 80');
    expect(fit(300), 'refs 70');
  });
}
