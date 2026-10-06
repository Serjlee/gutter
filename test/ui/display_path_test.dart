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

  test('displayPath on Windows', () {
    const home = r'C:\Users\luca';
    String show(String path) => displayPath(path, home: home, separator: r'\');
    expect(show(r'C:\Users\luca\code\app'), r'~\code\app');
    expect(show(home), '~');
    expect(show(r'C:\Users\lucas\app'), r'C:\Users\lucas\app');
    expect(show(r'D:\repo'), r'D:\repo');
  });
}
