import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/natural_sort.dart';

void main() {
  test('numbers sort as numbers', () {
    final names = [
      'ticket-10',
      'ticket-2',
      'Ticket-1',
      'fix/pr-100',
      'fix/pr-9',
      'ticket-02',
      'alpha',
    ]..sort(compareNatural);
    expect(names, [
      'alpha',
      'fix/pr-9',
      'fix/pr-100',
      'Ticket-1',
      'ticket-2',
      'ticket-02',
      'ticket-10',
    ]);
  });
}
