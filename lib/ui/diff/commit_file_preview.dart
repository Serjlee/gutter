import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../git/git_runner.dart';
import '../../git/models.dart';
import '../../git/parsers/diff_parser.dart';
import '../dialogs/dialogs.dart';
import '../repo/repo_tab_controller.dart';
import 'diff_view.dart';

/// Shows what a commit changed in one file, over whatever is open (the
/// rebase editor), leaving the tab's own diff alone.
Future<void> showCommitFilePreview(
  BuildContext context,
  RepoTabController tab,
  Commit commit,
  FileChange file,
) async {
  // The dialog is the top route while it's open.
  final nav = Navigator.of(context, rootNavigator: true);
  final source = CommitFileDiff(
    tab,
    CommitFileTarget(commit, file),
    onClose: nav.pop,
  );
  await showAppDialog<void>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        key: const ValueKey('commit-file-preview'),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width * 0.85,
          height: size.height * 0.85,
          child: ListenableBuilder(
            listenable: source,
            builder: (_, _) => DiffView(tab: tab, source: source),
          ),
        ),
      );
    },
  );
  source.dispose();
}

/// One commit file's diff, loaded once.
class CommitFileDiff extends ChangeNotifier implements DiffSource {
  CommitFileDiff(this.tab, this.target, {required this.onClose}) {
    unawaited(_load());
  }

  final RepoTabController tab;
  final CommitFileTarget target;
  final VoidCallback onClose;

  @override
  DiffTarget get diffTarget => target;
  @override
  FileDiff? diff;
  @override
  bool diffLoading = true;
  @override
  String? diffError;

  bool _disposed = false;

  Future<void> _load() async {
    try {
      diff = await tab.repo.commitFileDiff(target.commit, target.file);
    } catch (e) {
      diffError = e is GitException ? e.message : e.toString();
    }
    diffLoading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void closeDiff() => onClose();

  @override
  Future<Uint8List?> previewBytes() => tab.targetBytes(target);

  @override
  Future<(String?, String?)> diffFileTexts(DiffTarget target) =>
      tab.diffFileTexts(target);
}
