import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/ui/widgets/common.dart';

void main() {
  test('displayPath shortens the home folder to ~', () {
    const home = '/Users/luca';
    expect(displayPath('/Users/luca/code/app', home: home), '~/code/app');
    expect(displayPath('/Users/luca', home: home), '~');
    expect(displayPath('/Users/lucas/app', home: home), '/Users/lucas/app');
    expect(displayPath('/opt/repo', home: home), '/opt/repo');
    expect(displayPath('/opt/repo', home: '/'), '/opt/repo');
    expect(displayPath('/Users/luca/x', home: '/Users/luca/'), '~/x');
  });
}
