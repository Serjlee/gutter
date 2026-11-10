import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/open_with.dart' show desktopPrefix;
import '../dialogs/settings_dialog.dart';
import '../widgets/common.dart';

IconData openWithIcon(String id) => switch (id) {
  AppController.fileManagerId => Icons.folder_open,
  AppController.vsCodeId => Icons.code,
  // An installed app, or a command.
  _ when id.startsWith(desktopPrefix) || id.endsWith('.app') => Icons.apps,
  _ => Icons.terminal,
};

/// "Open in …" for each app [repo] can open with. In the repository's
/// own view ([repoView]), with the file manager's shortcut and "Manage…"
/// (the settings' Apps).
List<PopupMenuEntry<VoidCallback>> openWithItems(
  BuildContext context,
  AppController app,
  String repo, {
  bool repoView = true,
}) {
  return [
    for (final id in app.openWithIds)
      menuItem(
        id == AppController.fileManagerId
            ? 'Show in ${app.openWithName(id)}'
            : 'Open in ${app.openWithName(id)}',
        () => app.openRepoWith(repo, id),
        icon: openWithIcon(id),
        hint: repoView && id == AppController.fileManagerId
            ? shortcut('O', shift: true)
            : null,
      ),
    if (repoView) ...[
      const PopupMenuDivider(),
      menuItem(
        'Manage…',
        () => showSettingsDialog(context, app, section: SettingsSection.apps),
        icon: Icons.tune,
      ),
    ],
  ];
}
