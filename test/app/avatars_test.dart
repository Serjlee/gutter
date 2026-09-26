import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/avatars.dart';

Future<Uint8List> _png(int size) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('finds GitHub repositories in remote URLs', () {
    for (final url in [
      'https://github.com/serjlee/gutter.git',
      'https://github.com/serjlee/gutter',
      'https://user@github.com/serjlee/gutter/',
      'git@github.com:serjlee/gutter.git',
      'ssh://git@github.com/serjlee/gutter.git',
    ]) {
      expect(githubRepoOf(url), 'serjlee/gutter', reason: url);
    }
    expect(githubRepoOf('git@gitlab.com:serjlee/gutter.git'), isNull);
    expect(githubRepoOf('/srv/git/gutter.git'), isNull);
  });

  test('noreply addresses name their account; others go by email', () {
    expect(
      noreplyAvatarUrl('123+octo@users.noreply.github.com'),
      'https://avatars.githubusercontent.com/u/123?v=4',
    );
    expect(
      noreplyAvatarUrl('octo@users.noreply.github.com'),
      'https://github.com/octo.png',
    );
    expect(noreplyAvatarUrl('octo@example.com'), isNull);
    expect(
      emailAvatarUrl('a+b@x.io'),
      'https://avatars.githubusercontent.com/u/e?email=a%2Bb%40x.io',
    );
  });

  group('AvatarService', () {
    late Uint8List avatar, placeholder;
    late List<Uri> requests;
    late Directory dir;

    setUpAll(() async {
      avatar = await _png(AvatarService.size);
      placeholder = await _png(420); // the server's, for unknown emails
    });

    setUp(() async {
      requests = [];
      dir = await Directory.systemTemp.createTemp('gutter_avatars_');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    AvatarService service({Uint8List? Function(Uri)? respond}) => AvatarService(
      cacheFile: File('${dir.path}/avatars.json'),
      getBytes: (url) async {
        requests.add(url);
        return respond == null ? avatar : respond(url);
      },
    );

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('loads a picture by email, once', () async {
      final s = service();
      expect(s.imageFor('Ada@X.io'), isNull); // loading
      expect(s.imageFor('ada@x.io'), isNull); // not asked twice
      await settle();
      expect(s.imageFor('ada@x.io')?.width, AvatarService.size);
      expect(requests, hasLength(1));
      expect(requests.single.host, 'avatars.githubusercontent.com');
      expect(requests.single.queryParameters, {
        'email': 'ada@x.io',
        's': '${AvatarService.size}',
      });

      s.imageFor('7+dee@users.noreply.github.com');
      await settle();
      expect(requests.last.path, '/u/7');
    });

    test('the placeholder means no account, remembered', () async {
      final s = service(respond: (_) => placeholder);
      s.imageFor('bob@x.io');
      await settle();
      expect(s.imageFor('bob@x.io'), isNull);
      expect(s.hasNone('bob@x.io'), isTrue);
      s.save();

      requests.clear();
      final again = service();
      expect(again.imageFor('bob@x.io'), isNull);
      await settle();
      expect(requests, isEmpty);
    });

    test('offline: initials, and no retry this session', () async {
      final s = service(respond: (_) => null);
      s.imageFor('carl@x.io');
      await settle();
      s.imageFor('carl@x.io');
      await settle();
      expect(requests, hasLength(1));
      expect(s.hasNone('carl@x.io'), isFalse); // asked again next time
    });

    test('nothing when off', () async {
      final s = service()..enabled = false;
      expect(s.imageFor('ada@x.io'), isNull);
      await settle();
      expect(requests, isEmpty);
    });
  });
}
