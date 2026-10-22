import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../app/update_checker.dart';
import '../../app/updater.dart';
import '../widgets/common.dart';
import 'dialogs.dart';

/// Offers the latest release: its notes, then download, install and restart
/// (or a plain download where Gutter can't replace itself).
Future<void> showUpdateDialog(BuildContext context, AppController app) async {
  final release = app.updates.latest;
  if (release == null) return;
  await showAppDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(app: app, release: release),
  );
}

/// The release notes proper: the tag's message, without the install notes
/// CI appends after a `---` rule (in early releases, under an Installation
/// heading, or alone), and without Markdown markers.
String releaseNotesText(String notes) {
  notes = notes.replaceAll('\r\n', '\n');
  final i = notes.indexOf(
    RegExp(r'^(---\s*$|#+\s*Installation|\*\*macOS\*\*)', multiLine: true),
  );
  final text = (i < 0 ? notes : notes.substring(0, i)).trim();
  return text
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll('`', '');
}

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key, required this.app, required this.release});
  final AppController app;
  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final updater = app.updater;
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final install = updater.installation;
        final mine = updater.release?.tag == release.tag;
        final stage = mine ? updater.stage : UpdateStage.idle;
        // What's new since this build, release by release.
        final news = app.updates.newReleases;
        final current = app.updates.current;
        return AlertDialog(
          title: Text(
            'Gutter ${release.version} is available',
            style: const TextStyle(fontSize: 17),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You have ${current.isRelease ? current.version : current.label}.',
                  style: TextStyle(color: AppColors.textDim),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('update-notes'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, r)
                              in (news.isEmpty ? [release] : news).indexed) ...[
                            if (i > 0) const SizedBox(height: 14),
                            _ReleaseNotes(r),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _status(stage, install),
              ],
            ),
          ),
          actions: _actions(context, stage, install),
        );
      },
    );
  }

  Widget _status(UpdateStage stage, Installation install) {
    final updater = app.updater;
    final dim = TextStyle(fontSize: 12.5, color: AppColors.textDim);
    switch (stage) {
      case UpdateStage.downloading:
        final pct = updater.progress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 6),
            Text(
              install.kind == InstallKind.flatpak
                  ? 'Updating with Flatpak…'
                  : pct == null
                  ? 'Downloading…'
                  : 'Downloading… ${(pct * 100).round()}%',
              style: dim,
            ),
          ],
        );
      case UpdateStage.unpacking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 6),
            Text('Checking and unpacking…', style: dim),
          ],
        );
      case UpdateStage.ready:
        return Text(
          install.kind == InstallKind.flatpak
              ? 'Updated. Restart Gutter now, or the new version starts next '
                    'time.'
              : 'Ready. Restart Gutter now, or it updates when you quit.',
          style: dim,
        );
      case UpdateStage.scheduled:
        return Text(
          'Gutter updates when you quit, and starts the new version next '
          'time.',
          style: dim,
        );
      case UpdateStage.failed:
        return Text(
          'Update failed: ${updater.error}',
          style: TextStyle(fontSize: 12.5, color: AppColors.danger),
        );
      case UpdateStage.idle:
        return switch (install.kind) {
          InstallKind.flatpak => Text(
            'Gutter updates with Flatpak, from its repository.',
            style: dim,
          ),
          InstallKind.unsupported => Text(
            '${install.reason} You can download it from the release page.',
            style: dim,
          ),
          _ => const SizedBox.shrink(),
        };
    }
  }

  List<Widget> _actions(
    BuildContext context,
    UpdateStage stage,
    Installation install,
  ) {
    final updater = app.updater;
    void close() => Navigator.pop(context);
    final later = TextButton(
      key: const ValueKey('update-later'),
      onPressed: close,
      child: const Text('Later'),
    );
    switch (stage) {
      case UpdateStage.downloading:
      case UpdateStage.unpacking:
        return [later];
      case UpdateStage.ready:
        return [
          // A Flatpak is already updated: there's nothing to do on quit.
          if (install.kind == InstallKind.flatpak)
            later
          else
            TextButton(
              key: const ValueKey('update-on-quit'),
              onPressed: () async {
                await updater.install(relaunch: false);
                if (context.mounted) close();
              },
              child: const Text('Install on quit'),
            ),
          FilledButton(
            key: const ValueKey('update-restart'),
            autofocus: true,
            onPressed: () async {
              final busy = app.tabs.where((t) => t.busy != null).firstOrNull;
              if (busy != null) {
                app.notify(
                  'Wait for "${busy.busy}" to finish, then restart.',
                  warning: true,
                );
                return;
              }
              await updater.install(relaunch: true);
              app.quitForUpdate();
            },
            child: const Text('Restart now'),
          ),
        ];
      case UpdateStage.scheduled:
        return [
          FilledButton(
            autofocus: true,
            onPressed: close,
            child: const Text('OK'),
          ),
        ];
      case UpdateStage.idle:
      case UpdateStage.failed:
        final skip = TextButton(
          key: const ValueKey('update-skip'),
          onPressed: () {
            app.skipUpdate(release.tag);
            close();
          },
          child: const Text('Skip this version'),
        );
        final page = OutlinedButton(
          onPressed: () => openWithSystem(release.url),
          child: const Text('Release page'),
        );
        if (!install.canSelfUpdate) return [skip, later, page];
        return [
          skip,
          if (stage == UpdateStage.failed) page,
          later,
          FilledButton(
            key: const ValueKey('update-download'),
            autofocus: true,
            onPressed: () => updater.prepare(release),
            child: Text(
              stage == UpdateStage.failed
                  ? 'Try again'
                  : install.kind == InstallKind.flatpak
                  ? 'Update now'
                  : 'Download & Update',
            ),
          ),
        ];
    }
  }
}

/// One release's version, date and notes.
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes(this.release);
  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final notes = releaseNotesText(release.notes);
    final date = release.publishedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: release.version,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (date != null)
                TextSpan(
                  text: '   ${formatDate(date.toLocal()).substring(0, 10)}',
                  style: TextStyle(color: AppColors.textDim),
                ),
            ],
          ),
          style: const TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        SelectableText(
          notes.isEmpty ? 'No release notes.' : notes,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: notes.isEmpty ? AppColors.textDim : null,
          ),
        ),
      ],
    );
  }
}
