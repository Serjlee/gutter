/// Plain data types describing git objects as the UI needs them.
library;

class Commit {
  Commit({
    required this.sha,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authorTime,
    required this.subject,
  });

  final String sha;
  final List<String> parents;
  final String authorName;
  final String authorEmail;

  /// Seconds since epoch.
  final int authorTime;
  final String subject;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
  bool get isMerge => parents.length > 1;
  DateTime get date =>
      DateTime.fromMillisecondsSinceEpoch(authorTime * 1000, isUtc: false);

  String get initials {
    final parts = authorName
        .trim()
        .split(RegExp(r'[\s._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Full commit information shown in the details panel.
class CommitDetails {
  CommitDetails({
    required this.sha,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authorTime,
    required this.committerName,
    required this.committerEmail,
    required this.committerTime,
    required this.message,
  });

  final String sha;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final int authorTime;
  final String committerName;
  final String committerEmail;
  final int committerTime;
  final String message;

  String get subject => message.split('\n').first;
  String get body {
    final i = message.indexOf('\n');
    return i < 0 ? '' : message.substring(i + 1).trim();
  }
}

enum RefType { localBranch, remoteBranch, tag, stash, head }

class GitRef {
  GitRef({
    required this.fullName,
    required this.sha,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.upstreamGone = false,
    this.isHead = false,
    this.subject = '',
  });

  /// e.g. refs/heads/main, refs/remotes/origin/main, refs/tags/v1.
  final String fullName;

  /// The commit the ref points to (tags are peeled to the commit).
  final String sha;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool upstreamGone;
  final bool isHead;
  final String subject;

  RefType get type {
    if (fullName.startsWith('refs/heads/')) return RefType.localBranch;
    if (fullName.startsWith('refs/remotes/')) return RefType.remoteBranch;
    if (fullName.startsWith('refs/tags/')) return RefType.tag;
    if (fullName == 'refs/stash') return RefType.stash;
    return RefType.head;
  }

  /// Short display name, e.g. `main`, `origin/main`, `v1.0`.
  String get name {
    for (final p in const ['refs/heads/', 'refs/remotes/', 'refs/tags/']) {
      if (fullName.startsWith(p)) return fullName.substring(p.length);
    }
    return fullName;
  }

  /// For remote branches: the remote name (`origin`).
  String get remote {
    final n = name;
    final i = n.indexOf('/');
    return i < 0 ? n : n.substring(0, i);
  }

  /// For remote branches: branch name without the remote (`main`).
  String get remoteBranchName {
    final n = name;
    final i = n.indexOf('/');
    return i < 0 ? n : n.substring(i + 1);
  }

  /// `origin/HEAD` symbolic refs are noise in the UI.
  bool get isRemoteHead =>
      type == RefType.remoteBranch && remoteBranchName == 'HEAD';
}

/// What [Repository.checkoutRemote] did with the local branch.
enum RemoteCheckout {
  /// No local branch existed: a tracking branch was created.
  created,
  upToDate,

  /// The local branch was behind and now matches the remote.
  fastForwarded,

  /// The local branch has commits the remote doesn't (left as is).
  ahead,

  /// Both have their own commits (left as is).
  diverged,
}

class StashEntry {
  StashEntry({
    required this.index,
    required this.sha,
    required this.message,
    required this.time,
    required this.parents,
    this.authorName = '',
    this.authorEmail = '',
  });

  final int index;
  final String sha;
  final String message;

  /// Seconds since epoch.
  final int time;

  /// The commit the stash was made on, then its index (and untracked files)
  /// commits.
  final List<String> parents;
  final String authorName;
  final String authorEmail;

  String get ref => 'stash@{$index}';

  /// The commit the stash was made on.
  String? get base => parents.isEmpty ? null : parents.first;
}

/// Change kinds used both for commit file lists and working tree status.
enum ChangeKind {
  added,
  modified,
  deleted,
  renamed,
  copied,
  typeChanged,
  untracked,
  conflicted,
  unknown,
}

ChangeKind changeKindFromLetter(String c) {
  switch (c) {
    case 'A':
      return ChangeKind.added;
    case 'M':
      return ChangeKind.modified;
    case 'D':
      return ChangeKind.deleted;
    case 'R':
      return ChangeKind.renamed;
    case 'C':
      return ChangeKind.copied;
    case 'T':
      return ChangeKind.typeChanged;
    case 'U':
      return ChangeKind.conflicted;
    case '?':
      return ChangeKind.untracked;
    default:
      return ChangeKind.unknown;
  }
}

class FileChange {
  FileChange({required this.path, required this.kind, this.oldPath});

  final String path;
  final String? oldPath;
  final ChangeKind kind;

  @override
  String toString() => 'FileChange($kind $oldPath -> $path)';
}

/// One entry of `git status --porcelain=v2`.
class StatusEntry {
  StatusEntry({
    required this.path,
    this.oldPath,
    required this.index,
    required this.worktree,
    this.conflicted = false,
    this.conflictCode = '',
  });

  final String path;
  final String? oldPath;

  /// Staged change, or null if nothing staged.
  final ChangeKind? index;

  /// Unstaged change, or null if the worktree matches the index.
  final ChangeKind? worktree;
  final bool conflicted;

  /// Two-letter unmerged code (e.g. `UU`, `AA`, `DU`).
  final String conflictCode;

  bool get isUntracked => worktree == ChangeKind.untracked;
  bool get hasStaged => index != null && !conflicted;
  bool get hasUnstaged => worktree != null || conflicted;
}

class BranchStatus {
  const BranchStatus({
    this.head,
    this.oid,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  /// Branch name, or null when detached.
  final String? head;
  final String? oid;
  final String? upstream;
  final int ahead;
  final int behind;

  bool get detached => head == null;
}

class WorkingTreeStatus {
  WorkingTreeStatus({required this.branch, required this.entries});

  final BranchStatus branch;
  final List<StatusEntry> entries;

  static final empty = WorkingTreeStatus(
    branch: const BranchStatus(),
    entries: const [],
  );

  List<StatusEntry> get staged => entries.where((e) => e.hasStaged).toList();
  List<StatusEntry> get unstaged =>
      entries.where((e) => e.hasUnstaged).toList();
  List<StatusEntry> get conflicted =>
      entries.where((e) => e.conflicted).toList();
  bool get isClean => entries.isEmpty;
}

/// A multi-step operation that git is in the middle of.
enum RepoOperation { none, merge, rebase, cherryPick, revert, bisect }

extension RepoOperationLabel on RepoOperation {
  String get label {
    switch (this) {
      case RepoOperation.none:
        return '';
      case RepoOperation.merge:
        return 'Merge';
      case RepoOperation.rebase:
        return 'Rebase';
      case RepoOperation.cherryPick:
        return 'Cherry-pick';
      case RepoOperation.revert:
        return 'Revert';
      case RepoOperation.bisect:
        return 'Bisect';
    }
  }

  /// Subcommand used for --continue / --abort.
  String get command {
    switch (this) {
      case RepoOperation.merge:
        return 'merge';
      case RepoOperation.rebase:
        return 'rebase';
      case RepoOperation.cherryPick:
        return 'cherry-pick';
      case RepoOperation.revert:
        return 'revert';
      case RepoOperation.bisect:
        return 'bisect';
      case RepoOperation.none:
        return '';
    }
  }
}

class RemoteInfo {
  RemoteInfo({required this.name, required this.fetchUrl, this.pushUrl});
  final String name;
  final String fetchUrl;
  final String? pushUrl;
}
