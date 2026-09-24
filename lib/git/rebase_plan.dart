/// Interactive rebase planning.
///
/// The plan is turned into a complete todo list which replaces the one git
/// generates (via `GIT_SEQUENCE_EDITOR="cp <todo>"`), so git never needs an
/// interactive editor. Rewording and squashing are implemented with
/// `exec git commit --amend -F <file>` steps carrying the message the user
/// typed in the dialog.
library;

enum RebaseAction { pick, reword, edit, squash, fixup, drop }

extension RebaseActionInfo on RebaseAction {
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Folds into the previous kept commit.
  bool get folds => this == RebaseAction.squash || this == RebaseAction.fixup;
}

class RebaseStep {
  RebaseStep({
    required this.sha,
    required this.subject,
    required this.message,
    this.action = RebaseAction.pick,
    String? newMessage,
  }) : newMessage = newMessage ?? message;

  final String sha;
  final String subject;

  /// Original full message.
  final String message;
  RebaseAction action;

  /// Message to use for reword, or for the head of a squash group.
  String newMessage;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

class RebasePlanError implements Exception {
  RebasePlanError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One output group: a kept commit followed by the commits folded into it.
class RebaseGroup {
  RebaseGroup(this.head);
  final RebaseStep head;
  final folded = <RebaseStep>[];

  bool get hasSquash => folded.any((s) => s.action == RebaseAction.squash);

  /// Default combined message for a squash group (fixup messages dropped).
  String defaultMessage() {
    final parts = <String>[head.newMessage.trim()];
    for (final s in folded) {
      if (s.action == RebaseAction.squash) parts.add(s.message.trim());
    }
    return parts.join('\n\n');
  }
}

class RebasePlan {
  RebasePlan(this.steps);

  /// Oldest first, as in git's todo list.
  final List<RebaseStep> steps;

  List<RebaseGroup> groups() {
    final out = <RebaseGroup>[];
    for (final s in steps) {
      if (s.action == RebaseAction.drop) continue;
      if (s.action.folds) {
        if (out.isEmpty) {
          throw RebasePlanError(
            'The first kept commit (${s.shortSha}) cannot be squashed or '
            'fixed up: there is no earlier commit to fold it into.',
          );
        }
        out.last.folded.add(s);
      } else {
        out.add(RebaseGroup(s));
      }
    }
    return out;
  }

  void validate() => groups();

  /// Produces the todo text. [writeMessage] must persist a message and
  /// return the path of the file containing it.
  String buildTodo(String Function(String message) writeMessage) {
    final groups = this.groups();
    final lines = <String>[];
    // Emit drops for clarity (and so rebase.missingCommitsCheck is happy).
    final dropped = steps.where((s) => s.action == RebaseAction.drop);
    for (final g in groups) {
      final head = g.head;
      final verb = head.action == RebaseAction.edit ? 'edit' : 'pick';
      lines.add('$verb ${head.sha} ${head.subject}');
      for (final f in g.folded) {
        lines.add('fixup ${f.sha} ${f.subject}');
      }
      final needsMessage = head.action == RebaseAction.reword || g.hasSquash;
      final changed = head.newMessage.trim() != head.message.trim();
      if (needsMessage && (changed || g.hasSquash)) {
        final path = writeMessage(head.newMessage);
        lines.add(
          'exec git commit --amend --only --allow-empty --no-verify '
          '-F ${shellQuote(path)}',
        );
      }
    }
    for (final d in dropped) {
      lines.add('drop ${d.sha} ${d.subject}');
    }
    return '${lines.join('\n')}\n';
  }
}

/// Presets [steps] (oldest first) so the commits in [shas] are squashed
/// into the oldest of them. Returns false, changing nothing, unless they
/// are all among [steps] and consecutive.
bool presetSquash(List<RebaseStep> steps, Set<String> shas) {
  final idx = [
    for (var i = 0; i < steps.length; i++)
      if (shas.contains(steps[i].sha)) i,
  ];
  if (idx.length < 2 ||
      idx.length != shas.length ||
      idx.last - idx.first != idx.length - 1) {
    return false;
  }
  steps[idx.first].action = RebaseAction.pick;
  for (final i in idx.skip(1)) {
    steps[i].action = RebaseAction.squash;
  }
  return true;
}

String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";
