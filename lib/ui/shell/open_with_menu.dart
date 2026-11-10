import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../dialogs/settings_dialog.dart';
import '../widgets/common.dart';

IconData openWithIcon(String id) => switch (id) {
  AppController.fileManagerId => Icons.folder_open,
  AppController.vsCodeId => Icons.code,
  _ => Icons.terminal,
};

/// "Open in …" for each app [repo] can open with, and "Manage…" (the
/// settings' Apps).
List<PopupMenuEntry<VoidCallback>> openWithItems(
  BuildContext context,
  AppController app,
  String repo,
) {
  return [
    for (final id in app.openWithIds)
      menuItem(
        id == AppController.fileManagerId
            ? 'Show in ${app.openWithName(id)}'
            : 'Open in ${app.openWithName(id)}',
        () => app.openRepoWith(repo, id),
        icon: openWithIcon(id),
        hint: id == AppController.fileManagerId
            ? shortcut('O', shift: true)
            : null,
      ),
    const PopupMenuDivider(),
    menuItem(
      'Manage…',
      () => showSettingsDialog(context, app, section: SettingsSection.apps),
      icon: Icons.tune,
    ),
  ];
}
