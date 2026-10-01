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
/// CI appends after a `---` rule, and without Markdown markers.
String releaseNotesText(String notes) {
  final i = notes.indexOf(RegExp(r'^---\s*$', multiLine: true));
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
        final notes = releaseNotesText(release.notes);
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
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          notes,
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
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
              pct == null
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
          'Ready. Restart Gutter now, or it updates when you quit.',
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
            'Installed with Flatpak: download the new bundle, then install it '
            'with `flatpak install --user <file>`.',
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
        if (install.kind == InstallKind.flatpak) {
          final asset = install.assetIn(release);
          return [
            skip,
            later,
            FilledButton(
              autofocus: true,
              onPressed: () {
                openWithSystem(asset?.url ?? release.url);
                close();
              },
              child: const Text('Download'),
            ),
          ];
        }
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
              stage == UpdateStage.failed ? 'Try again' : 'Download & Update',
            ),
          ),
        ];
    }
  }
}
