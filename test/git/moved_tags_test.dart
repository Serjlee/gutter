import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/git_errors.dart';
import 'package:gutter/git/git_runner.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/repo/repo_view.dart';

import '../support/temp_repo.dart';

/// A clone of an upstream whose "dev" tag then moved.
Future<(TempRepo, TempRepo)> _movedTag() async {
  final upstream = await TempRepo.create();
  upstream.commit('one', {'a.txt': 'a\n'});
  upstream.git(['tag', 'dev']);
  final t = await TempRepo.create();
  t.commit('local', {'b.txt': 'b\n'});
  t.git(['remote', 'add', 'origin', upstream.path]);
  t.git(['fetch', '-q', '--tags', 'origin']);
  upstream.commit('two', {'a.txt': 'b\n'});
  upstream.git(['tag', '-f', 'dev']);
  return (upstream, t);
}

String _sha(TempRepo r, String rev) => r.git(['rev-parse', rev]).trim();

void main() {
  late TempRepo upstream;
  late TempRepo t;
  setUp(() async => (upstream, t) = await _movedTag());
  tearDown(() {
    t.dispose();
    upstream.dispose();
  });

  test(
    'a fetch lists the tags it didn\'t move; forced, it moves them',
    () async {
      final e = await t.repo.fetch().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(e, isA<GitException>());
      expect(movedTagsIn(e! as GitException), ['dev']);
      expect(onlyTagsMoved(e as GitException), isTrue);
      // The rest was fetched.
      expect(_sha(t, 'origin/main'), _sha(upstream, 'HEAD'));
      expect(_sha(t, 'dev'), isNot(_sha(upstream, 'dev')));

      await t.repo.fetch(forceTags: true);
      expect(_sha(t, 'dev'), _sha(upstream, 'dev'));
    },
  );

  test('other rejections and errors are real failures', () {
    GitException err(String stderr) => GitException(['fetch'], 1, stderr);
    const moved =
        ' ! [rejected]        dev        -> dev  (would clobber existing tag)\n';
    expect(onlyTagsMoved(err(moved)), isTrue);
    expect(
      onlyTagsMoved(
        err(
          '$moved ! [rejected]        main       -> origin/main  '
          '(non-fast-forward)\n',
        ),
      ),
      isFalse,
    );
    expect(
      onlyTagsMoved(err('${moved}fatal: Could not read from remote\n')),
      isFalse,
    );
    expect(summarizeGitError(err(moved)), contains('Force Tag Fetch'));
  });

  test(
    'the tab: moved tags aren\'t a failed fetch; the setting forces',
    () async {
      final tab = RepoTabController(t.repo, AppController(null, Settings()));
      addTearDown(tab.dispose);
      await tab.load();
      await tab.fetch();
      expect(tab.fetchError, isNull);
      expect(tab.movedTags, ['dev']);

      // Offered once per set of tags, and again after a manual fetch; not
      // while the forced fetch runs.
      tab.setActive(true);
      expect(tab.takeMovedTagsPrompt(), isTrue);
      expect(tab.takeMovedTagsPrompt(), isFalse);
      await tab.fetch(auto: true);
      expect(tab.takeMovedTagsPrompt(), isFalse);
      await tab.fetch();
      expect(tab.takeMovedTagsPrompt(), isTrue); // the popup opens
      var offered = 0;
      void listener() => offered += tab.takeMovedTagsPrompt() ? 1 : 0;
      tab.addListener(listener);
      await tab.fetch(forceTags: true);
      tab.removeListener(listener);
      expect(offered, 0);
      expect(tab.movedTags, isEmpty);

      upstream.commit('three', {'a.txt': 'c\n'});
      upstream.git(['tag', '-f', 'dev']);
      tab.app.settings.forceTagFetch = true;
      await tab.fetch(auto: true);
      expect(tab.movedTags, isEmpty);
      expect(_sha(t, 'dev'), _sha(upstream, 'dev'));
    },
  );

  testWidgets('the popup forces the fetch, and can always do so', (
    tester,
  ) async {
    late RepoTabController tab;
    await tester.runAsync(() async {
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      await tab.fetch();
    });
    addTearDown(tab.dispose);
    expect(tab.movedTags, ['dev']);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMovedTags(context, tab),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('A tag moved on the remote'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('force-tag-fetch-always')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('force-tag-fetch')));
    // The fetch runs git: let real time pass, and the fake clock.
    for (
      var i = 0;
      i < 200 && (tab.fetching || tab.movedTags.isNotEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tab.movedTags, isEmpty);
    expect(tab.app.settings.forceTagFetch, isTrue);
    expect(_sha(t, 'dev'), _sha(upstream, 'dev'));
  });
}
