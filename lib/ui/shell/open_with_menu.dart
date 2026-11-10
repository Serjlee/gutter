import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/open_with.dart' show desktopPrefix;
import '../../app/theme.dart';
import '../widgets/common.dart';

/// The icons an app to open with can be given, by key.
const openWithIconChoices = <String, IconData>{
  'code': Icons.code,
  'terminal': Icons.terminal,
  'edit': Icons.edit_note,
  'apps': Icons.apps,
  'article': Icons.article_outlined,
  'data': Icons.data_object,
  'bug': Icons.bug_report_outlined,
  'build': Icons.build_outlined,
  'web': Icons.language,
  'merge': Icons.merge_type,
  'brush': Icons.brush_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'cloud': Icons.cloud_outlined,
  'star': Icons.star_outline,
  'bolt': Icons.bolt,
  'chat': Icons.chat_bubble_outline,
};

/// How a picked image is saved among the apps' icons: this, then its path.
const imageIconPrefix = 'file:';

/// The icon of the app [id]: the one picked, else its own.
IconData openWithIcon(AppController app, String id) =>
    openWithIconChoices[app.settings.openWithIcons[id]] ??
    openWithDefaultIcon(id);

/// The image picked for the app [id], [size] square, if one is and its
/// file is there.
Widget? openWithImage(AppController app, String id, {double size = 16}) {
  final icon = app.settings.openWithIcons[id];
  if (icon == null || !icon.startsWith(imageIconPrefix)) return null;
  final file = File(icon.substring(imageIconPrefix.length));
  // Gone, its own icon is used instead.
  if (!file.existsSync()) return null;
  return Image.file(
    file,
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, _, _) =>
        Icon(openWithDefaultIcon(id), size: size, color: AppColors.textDim),
  );
}

/// The app [id]'s own icon.
IconData openWithDefaultIcon(String id) => switch (id) {
  AppController.fileManagerId => Icons.folder_open,
  AppController.vsCodeId => Icons.code,
  // An installed app, or a command.
  _ when id.startsWith(desktopPrefix) || id.endsWith('.app') => Icons.apps,
  _ => Icons.terminal,
};

/// What opening [repo] with the app [id] is called.
String openWithAction(AppController app, String id) =>
    id == AppController.fileManagerId
    ? 'Show in ${app.openWithName(id)}'
    : 'Open in ${app.openWithName(id)}';

/// Items opening [repo]: in the file manager, then in each app to open
/// with.
List<PopupMenuEntry<VoidCallback>> openWithItems(
  AppController app,
  String repo,
) => [
  for (final id in app.openWithIds)
    menuItem(
      openWithAction(app, id),
      () => app.openRepoWith(repo, id),
      icon: openWithIcon(app, id),
      leading: openWithImage(app, id),
    ),
];
