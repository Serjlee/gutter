import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/open_with.dart'
    show InstalledApp, desktopPrefix, openWithProblem;
import '../../app/settings_store.dart' show GraphMode;
import '../../app/theme.dart';
import '../../app/zoom.dart';
import '../../git/git_runner.dart';
import '../../graph/graph_painter.dart';
import '../widgets/common.dart';
import '../shell/open_with_menu.dart';
import 'dialogs.dart';

/// The settings, in a dialog, at [section]: from the dashboard, with ⌘,
/// (macOS) or Ctrl+, (or Ctrl+P), or from the app menu on macOS.
Future<void> showSettingsDialog(
  BuildContext context,
  AppController app, {
  SettingsSection section = SettingsSection.appearance,
}) => showAppDialog<void>(
  context: context,
  builder: (ctx) => Dialog(
    // Held at the top: switching sections changes its height.
    alignment: Alignment.topCenter,
    insetPadding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
    child: SizedBox(
      width: 600,
      child: _SettingsPanel(app: app, section: section),
    ),
  ),
);

enum SettingsSection {
  appearance('Appearance', Icons.palette_outlined),
  git('Git', Icons.call_split),
  apps('Apps', Icons.apps),
  performance('Performance', Icons.speed);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The sections as a toolbar of tabs on top (as macOS apps' settings
/// have them), the current one's settings, and Done.
class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({required this.app, required this.section});
  final AppController app;
  final SettingsSection section;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late var _section = widget.section;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final s in SettingsSection.values)
                _SectionTab(
                  section: s,
                  selected: s == _section,
                  onTap: () => setState(() => _section = s),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: AppColors.border),
        Flexible(
          // Grows or shrinks to the section, as macOS settings windows do.
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            // Always shown when there is more (easy to miss otherwise),
            // in the middle of the right margin.
            child: ScrollbarTheme(
              data: ScrollbarTheme.of(context).copyWith(
                thickness: const WidgetStatePropertyAll(6),
                crossAxisMargin: 7,
                mainAxisMargin: 8,
              ),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(20),
                  child: ListenableBuilder(
                    listenable: widget.app,
                    builder: (_, _) =>
                        SettingsForm(app: widget.app, section: _section),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('settings-close'),
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textDim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected
            ? AppColors.text.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          key: ValueKey('settings-tab-${section.name}'),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            width: 92,
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                Icon(section.icon, size: 20, color: color),
                const SizedBox(height: 3),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: selected ? AppColors.text : AppColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One section's settings, in groups.
class SettingsForm extends StatelessWidget {
  const SettingsForm({
    super.key,
    required this.app,
    this.section = SettingsSection.appearance,
  });
  final AppController app;
  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    final groups = switch (section) {
      SettingsSection.appearance => [
        [
          _Row('Zoom', control: _ZoomStepper(app: app)),
          _Row(
            'Theme',
            below: _TilePicker<String>(
              name: 'theme-mode',
              value: s.themeMode,
              columns: 3,
              items: [
                for (final (mode, label) in [
                  ('system', 'System'),
                  ('light', 'Light'),
                  ('dark', 'Dark'),
                ])
                  (mode, label, _ThemeThumb(mode)),
              ],
              onChanged: app.setThemeMode,
            ),
          ),
        ],
        [
          _Row(
            'Graph',
            below: _TilePicker<GraphMode>(
              name: 'graph-mode',
              value: s.graphMode,
              items: [
                for (final (mode, label) in [
                  (GraphMode.full, 'Full'),
                  (GraphMode.compact, 'Compact'),
                  (GraphMode.fork, 'Fork'),
                  (GraphMode.alignedFork, 'Aligned Fork'),
                ])
                  (mode, label, _GraphModePreview(mode)),
              ],
              onChanged: app.setGraphMode,
            ),
          ),
          _Row(
            'Line hint',
            below: _TilePicker<LineHint>(
              name: 'line-hint',
              value: s.lineHint,
              columns: 4,
              items: [
                for (final (hint, label) in [
                  (LineHint.fade, 'Fade'),
                  (LineHint.leader, 'Leader line'),
                  (LineHint.line, 'Line'),
                  (LineHint.none, 'None'),
                ])
                  (hint, label, _LineHintPreview(hint)),
              ],
              onChanged: app.setLineHint,
            ),
          ),
        ],
        [
          _Row(
            'GitHub avatars',
            subtitle: 'Authors\' profile pictures, for repositories on GitHub',
            info:
                'Gutter asks GitHub\'s avatar server for each author\'s '
                'picture by commit email (no API calls), as they come into '
                'view. Authors whose email isn\'t on a GitHub account keep '
                'their initials.',
            control: _Toggle(
              key: const ValueKey('github-avatars'),
              value: s.githubAvatars,
              onChanged: app.setGithubAvatars,
            ),
          ),
        ],
      ],
      SettingsSection.git => [
        [
          _Row(
            'Git executable',
            // What runs there (or why not), once checked.
            subtitle:
                app.gitProblem ??
                app.gitVersion ??
                'Leave empty to use the git Gutter finds',
            problem: app.gitProblem != null,
            control: SizedBox(width: 240, child: _GitPathField(app: app)),
          ),
        ],
        [
          _Row(
            'Auto-fetch',
            subtitle: 'Fetches open repositories in the background',
            control: AppDropdown<int>(
              value: s.fetchIntervalMinutes,
              items: const [
                (0, 'Off', null),
                (1, 'Every minute', null),
                (5, 'Every 5 min', null),
                (10, 'Every 10 min', null),
                (30, 'Every 30 min', null),
              ],
              onChanged: app.setFetchInterval,
            ),
          ),
          _Row(
            'Always force tag fetch',
            subtitle: 'Moves local tags that moved on the remote',
            info:
                'When a tag moved on the remote (deploy tags like "dev" or '
                '"staging" often do), git won\'t move your local one.\n\n'
                'Off: Gutter lists the moved tags and offers Force Tag '
                'Fetch, which replaces your local tags with the remote\'s.'
                '\n\nOn: every fetch does that, without asking.',
            control: _Toggle(
              key: const ValueKey('force-tag-fetch'),
              value: s.forceTagFetch,
              onChanged: app.setForceTagFetch,
            ),
          ),
        ],
      ],
      SettingsSection.apps => [
        [
          _AppList(app: app),
          _Row(
            'Add an app',
            subtitle:
                'An installed app, by name (Linux or macOS only), or a '
                'command',
            below: _AddAppField(app: app),
          ),
        ],
      ],
      SettingsSection.performance => [
        [
          _Row(
            'Commits loaded',
            subtitle: 'At a time: the bottom of the graph loads more',
            info:
                'How many commits a repository loads when it opens. '
                'Scrolling to the bottom of the graph loads the next batch '
                'of the same size, so older history is always reachable.\n\n'
                'All loads the whole history at once: simplest, but slower '
                'to open very large repositories.\n\n'
                'Applies to repositories opened from now on.',
            control: AppDropdown<int>(
              value: s.maxCommits,
              items: const [
                (2000, '2,000', null),
                (20000, '20,000', null),
                (100000, '100,000', null),
                (0, 'All', null),
              ],
              onChanged: app.setMaxCommits,
            ),
          ),
          _Row(
            'Syntax highlighting',
            subtitle: 'In diffs, file previews and conflicts',
            info:
                'Colors code for about 40 languages (by file extension). '
                'Very large files stay plain.',
            control: _Toggle(
              key: const ValueKey('syntax-highlighting'),
              value: s.syntaxHighlight,
              onChanged: app.setSyntaxHighlight,
            ),
          ),
        ],
      ],
    };
    final intro = switch (section) {
      SettingsSection.apps =>
        'External apps that can open a repository directory. Shortcuts '
            'will be added in the repository toolbar.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (intro != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
            child: Text(
              intro,
              style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
            ),
          ),
        for (final (i, rows) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          _Group(rows),
        ],
      ],
    );
  }
}

/// Rows in a rounded box, with hairlines between them.
class _Group extends StatelessWidget {
  const _Group(this.rows);
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final line = AppColors.border.withValues(alpha: 0.7);
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          AppColors.text.withValues(alpha: 0.035),
          AppColors.panel,
        ),
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: line,
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting: its name (and a line on what it does, an ⓘ with more) and
/// its [control] on the right, or a wider one [below].
class _Row extends StatelessWidget {
  const _Row(
    this.label, {
    this.subtitle,
    this.problem = false,
    this.info,
    this.control,
    this.below,
  });
  final String label;
  final String? subtitle;

  /// The subtitle says what is wrong: shown as an error.
  final bool problem;
  final String? info;
  final Widget? control;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (info != null) ...[
                          const SizedBox(width: 5),
                          _InfoIcon(message: info!, label: label),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          key: problem ? const ValueKey('row-problem') : null,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: problem
                                ? AppColors.danger
                                : AppColors.textDim,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (control != null) ...[const SizedBox(width: 12), control!],
            ],
          ),
          if (below != null) ...[const SizedBox(height: 12), below!],
        ],
      ),
    );
  }
}

/// Choices shown as what they look like, side by side, the current one
/// outlined (as macOS's own settings do). Tiles are keyed `name-value`.
class _TilePicker<T> extends StatelessWidget {
  const _TilePicker({
    required this.name,
    required this.value,
    required this.items,
    required this.onChanged,
    this.columns = 2,
  });
  final String name;
  final T value;

  /// (value, label, what it looks like) triples.
  final List<(T, String, Widget)> items;
  final ValueChanged<T> onChanged;
  final int columns;

  static String _id(Object? v) => v is Enum ? v.name : '$v';

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (var i = 0; i < items.length; i += columns)
        items.sublist(i, (i + columns).clamp(0, items.length)),
    ];
    return Column(
      key: ValueKey(name),
      children: [
        for (final (r, row) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (v, label, look)) in row.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: _tile(v, label, look)),
                  ],
                  // A short last row keeps the tiles' width.
                  for (var i = row.length; i < columns; i++) ...[
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(T v, String label, Widget look) {
    final selected = v == value;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('$name-${_id(v)}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(v),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  key: selected ? ValueKey('$name-selected') : null,
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: selected ? AppColors.accent : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: look,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.text : AppColors.textDim,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small window in a theme's colors; System is half light, half dark.
class _ThemeThumb extends StatelessWidget {
  const _ThemeThumb(this.mode);
  final String mode;

  static Widget _window(AppPalette p) => Container(
    width: 96,
    height: 56,
    decoration: BoxDecoration(
      color: p.background,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: p.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 10, color: p.toolbar),
        Expanded(
          child: Row(
            children: [
              Container(width: 22, color: p.panel),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, w) in [(0, 44.0), (1, 30.0), (0, 38.0)])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: AppColors.lane(i),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                width: w,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: p.textFaint,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => switch (mode) {
    'light' => _window(AppPalette.light),
    'dark' => _window(AppPalette.dark),
    _ => Stack(
      children: [
        _window(AppPalette.light),
        ClipRect(clipper: const _RightHalf(), child: _window(AppPalette.dark)),
      ],
    ),
  };
}

class _RightHalf extends CustomClipper<Rect> {
  const _RightHalf();
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width / 2, 0, size.width, size.height);
  @override
  bool shouldReclip(_RightHalf old) => false;
}

/// An on/off switch, small as macOS's.
class _Toggle extends StatelessWidget {
  const _Toggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 120);
    return Semantics(
      toggled: value,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: duration,
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value
                  ? AppColors.accent
                  : AppColors.text.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: AnimatedAlign(
              duration: duration,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// − 100% +; the percentage resets it.
class _ZoomStepper extends StatelessWidget {
  const _ZoomStepper({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final zoom = app.settings.zoom;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SmallIconButton(
          icon: Icons.remove,
          tooltip: 'Zoom out (${shortcut('-')})',
          onPressed: zoom > minZoom ? app.zoomOut : null,
        ),
        SizedBox(
          width: 46,
          child: InkWell(
            onTap: app.zoomReset,
            child: Text(
              '${(zoom * 100).round()}%',
              key: const ValueKey('zoom-value'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        SmallIconButton(
          icon: Icons.add,
          tooltip: 'Zoom in (${shortcut('+')})',
          onPressed: zoom < maxZoom ? app.zoomIn : null,
        ),
      ],
    );
  }
}

/// Three graph rows laid out as [mode] does it, as a sample.
class _GraphModePreview extends StatelessWidget {
  const _GraphModePreview(this.mode);
  final GraphMode mode;

  static const _rowH = 22.0;
  static const _headerH = 16.0;
  static const _labelsW = 50.0; // Full: their column
  static const _room = 46.0; // Compact: theirs in the graph column

  /// x of a lane's center.
  static double _lane(int lane) => 8.0 + lane * 12;

  /// Where the lanes in use at a row end.
  static double _lanesEnd(int lanes) => _lane(lanes - 1) + 9;

  @override
  Widget build(BuildContext context) {
    // (node lane, lanes in use, label, label color, message); the lanes
    // themselves are drawn by _PreviewLanes.
    final rows = [
      (0, 1, 'main', AppColors.lane(0), 'Fix typo'),
      (1, 2, null, AppColors.lane(1), 'Add login form'),
      (0, 2, 'v1.0', AppColors.tag, 'Merge login'),
    ];
    final graphX = mode == GraphMode.full ? _labelsW : 0.0;
    final graphW = _lanesEnd(2) + (mode == GraphMode.compact ? _room : 0) + 12;
    final text = TextStyle(fontSize: 11.5, color: AppColors.text);
    Widget pill(String label, Color color) => Container(
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.2),
          AppColors.background,
        ),
        border: Border.all(color: color.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9.5, height: 1, color: AppColors.pillText),
      ),
    );
    Widget message(String? label, Color color, String msg) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[pill(label, color), const SizedBox(width: 4)],
        Text(msg, style: text, maxLines: 1),
      ],
    );
    return SizedBox(
      width: 240,
      height: _headerH + _rowH * rows.length,
      child: Stack(
        children: [
          // The column headers, as the graph has them: Full's labels have
          // a column of their own, Compact's widen the graph's.
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: _headerH - 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
            ),
          ),
          for (final (name, x) in [
            if (mode == GraphMode.full) ('BRANCH', 0.0),
            ('GRAPH', graphX),
            ('MESSAGE', graphX + graphW),
          ]) ...[
            if (x > 0)
              Positioned(
                left: x - 4,
                top: 1,
                width: 1,
                height: _headerH - 5,
                child: ColoredBox(color: AppColors.border),
              ),
            Positioned(
              left: x,
              top: 0,
              height: _headerH - 3,
              child: Center(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 8,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            left: graphX,
            top: _headerH,
            width: graphW,
            bottom: 0,
            child: CustomPaint(painter: _PreviewLanes()),
          ),
          for (final (i, (_, lanes, label, color, msg)) in rows.indexed)
            ...switch (mode) {
              GraphMode.full => [
                if (label != null)
                  Positioned(
                    left: 0,
                    top: _headerH + i * _rowH + 3.5,
                    child: pill(label, color),
                  ),
                Positioned(
                  left: graphX + graphW,
                  top: _headerH + i * _rowH,
                  height: _rowH,
                  child: Center(child: Text(msg, style: text)),
                ),
              ],
              GraphMode.compact => [
                if (label != null)
                  Positioned(
                    left: _lanesEnd(lanes) + 2,
                    top: _headerH + i * _rowH + 3.5,
                    child: pill(label, color),
                  ),
                Positioned(
                  left: graphW,
                  top: _headerH + i * _rowH,
                  height: _rowH,
                  child: Center(child: Text(msg, style: text)),
                ),
              ],
              GraphMode.fork || GraphMode.alignedFork => [
                Positioned(
                  left: mode == GraphMode.fork ? _lanesEnd(lanes) + 4 : graphW,
                  top: _headerH + i * _rowH,
                  height: _rowH,
                  child: Center(child: message(label, color, msg)),
                ),
              ],
            },
        ],
      ),
    );
  }
}

/// The preview's lanes: main, and a branch merged back into it.
class _PreviewLanes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const h = _GraphModePreview._rowH;
    final x0 = _GraphModePreview._lane(0), x1 = _GraphModePreview._lane(1);
    final line = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(x0, 0),
      Offset(x0, size.height),
      line..color = AppColors.lane(0),
    );
    // The branch: from its commit down into the merge.
    canvas.drawPath(
      Path()
        ..moveTo(x1, h * 1.5)
        ..lineTo(x1, h * 2.2)
        ..quadraticBezierTo(x1, h * 2.5, x0 + 4, h * 2.5),
      line..color = AppColors.lane(1),
    );
    for (final (row, lane) in [(0, 0), (1, 1), (2, 0)]) {
      canvas.drawCircle(
        Offset(_GraphModePreview._lane(lane), (row + 0.5) * h),
        4.5,
        Paint()..color = AppColors.lane(lane),
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewLanes old) => false;
}

/// Two graph rows drawn with [hint], as a sample of what it looks like.
class _LineHintPreview extends StatelessWidget {
  const _LineHintPreview(this.hint);
  final LineHint hint;

  @override
  Widget build(BuildContext context) {
    final text = TextStyle(fontSize: 11.5, color: AppColors.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (lane, message) in [(0, 'Merge'), (1, 'Fix typo')])
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(44, 24),
                  painter: _LineHintRowPainter(hint, lane),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message,
                    style: text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineHintRowPainter extends CustomPainter {
  _LineHintRowPainter(this.hint, this.lane);
  final LineHint hint;
  final int lane;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int lane) => 8.0 + lane * 14;
    final line = Paint()..strokeWidth = 2;
    // The first lane runs through both rows; the second starts at its node.
    canvas.drawLine(
      Offset(x(0), 0),
      Offset(x(0), size.height),
      line..color = AppColors.lane(0),
    );
    if (lane == 1) {
      canvas.drawLine(
        Offset(x(1), size.height / 2),
        Offset(x(1), size.height),
        line..color = AppColors.lane(1),
      );
    }
    paintLineHint(
      canvas,
      hint,
      color: AppColors.lane(lane),
      from: x(lane),
      to: size.width,
      height: size.height,
    );
    canvas.drawCircle(
      Offset(x(lane), size.height / 2),
      5,
      Paint()..color = AppColors.lane(lane),
    );
  }

  @override
  bool shouldRepaint(_LineHintRowPainter old) =>
      old.hint != hint || old.lane != lane;
}

/// An ⓘ that explains a setting in a popover, on hover or click.
class _InfoIcon extends StatefulWidget {
  const _InfoIcon({required this.message, required this.label});
  final String message;
  final String label;

  @override
  State<_InfoIcon> createState() => _InfoIconState();
}

class _InfoIconState extends State<_InfoIcon> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltip,
      message: widget.message,
      showDuration: const Duration(seconds: 12),
      waitDuration: const Duration(milliseconds: 200),
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.all(12),
      textStyle: TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.4),
      decoration: BoxDecoration(
        color: AppColors.toolbar,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: GestureDetector(
        key: ValueKey('info-${widget.label}'),
        onTap: () => _tooltip.currentState?.ensureTooltipVisible(),
        child: MouseRegion(
          cursor: SystemMouseCursors.help,
          child: Icon(Icons.info_outline, size: 15, color: AppColors.textDim),
        ),
      ),
    );
  }
}

/// The apps to open with, in order (drag to reorder), each with its icon
/// and name to change, and Remove: a few, then they scroll.
class _AppList extends StatefulWidget {
  const _AppList({required this.app});
  final AppController app;

  @override
  State<_AppList> createState() => _AppListState();
}

class _AppListState extends State<_AppList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ids = app.settings.openWithApps;
    final header = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: AppColors.textDim,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The columns, named once.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _AppRow.leadWidth,
            10,
            _AppRow.trailWidth,
            2,
          ),
          child: Row(
            children: [
              Expanded(child: Text('APP', style: header)),
              SizedBox(
                width: _AppRow.showWidth,
                child: Center(child: Text('SHOW', style: header)),
              ),
            ],
          ),
        ),
        _list(app, ids),
      ],
    );
  }

  Widget _list(AppController app, List<String> ids) {
    return ConstrainedBox(
      // About four apps, the next one peeking out.
      constraints: const BoxConstraints(maxHeight: 230),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: ReorderableListView.builder(
          key: const ValueKey('app-list'),
          scrollController: _scroll,
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: ids.length,
          onReorderItem: app.moveOpenWithApp,
          proxyDecorator: (child, _, _) => Material(
            color: AppColors.panelAlt,
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
          itemBuilder: (context, i) =>
              _AppRow(key: ValueKey(ids[i]), app: app, id: ids[i], index: i),
        ),
      ),
    );
  }
}

/// An app to open with: its drag handle, icon, name (its own, as a hint,
/// until given one), what it runs, and Remove (VS Code, found, stays).
class _AppRow extends StatefulWidget {
  const _AppRow({
    super.key,
    required this.app,
    required this.id,
    required this.index,
  });
  final AppController app;
  final String id;
  final int index;

  /// What comes before the name (drag handle, icon), and after the Show
  /// column (Remove): for the header to line up.
  static const leadWidth = 6.0 + 26 + 4 + 32 + 10;
  static const trailWidth = 4.0 + 24 + 10;
  static const showWidth = 44.0;

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow> {
  late final _name = TextEditingController(
    text: widget.app.settings.openWithNames[widget.id] ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _rename() => widget.app.setOpenWithName(widget.id, _name.text);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final id = widget.id;
    // The file manager and VS Code: theirs, not to edit or remove.
    final builtIn =
        id == AppController.fileManagerId || id == AppController.vsCodeId;
    final missing = id == AppController.vsCodeId && app.vsCode == null;
    final runs = switch (id) {
      AppController.fileManagerId =>
        'Also ${shortcut('O', shift: true)}, in a repository',
      AppController.vsCodeId =>
        app.vsCode ?? 'Not found: its code command isn\'t installed',
      _ => id.replaceFirst(desktopPrefix, ''),
    };
    final row = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.index > 0)
          Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: AppColors.border.withValues(alpha: 0.7),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (builtIn)
                SizedBox.square(
                  dimension: 32,
                  child: Icon(
                    openWithIcon(app, id),
                    size: 18,
                    color: AppColors.textDim,
                  ),
                )
              else
                _IconPicker(app: app, id: id),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (builtIn)
                      Text(
                        id == AppController.fileManagerId &&
                                !Platform.isMacOS &&
                                !Platform.isWindows
                            ? 'File manager'
                            : app.openWithName(id),
                        style: const TextStyle(fontSize: 13),
                      )
                    else
                      Focus(
                        onFocusChange: (f) {
                          if (!f) _rename();
                        },
                        child: TextField(
                          key: ValueKey('app-name-$id'),
                          controller: _name,
                          onSubmitted: (_) => _rename(),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration.collapsed(
                            // Its own name, dim: given none, it goes by it.
                            hintText: app.openWithDefaultName(id),
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      runs,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _AppRow.showWidth,
                child: Tooltip(
                  message: 'A button for it in the repository\'s toolbar',
                  child: Checkbox(
                    key: ValueKey('app-show-$id'),
                    value: !app.settings.openWithHidden.contains(id),
                    onChanged: (v) => app.setOpenWithShown(id, v ?? true),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (builtIn)
                const SizedBox(width: 24)
              else
                SmallIconButton(
                  key: ValueKey('remove-app-$id'),
                  icon: Icons.close,
                  tooltip: 'Remove',
                  onPressed: () => app.removeOpenWithApp(id),
                ),
            ],
          ),
        ),
      ],
    );
    // VS Code, not found: dim, its place kept for when it is.
    return missing ? Opacity(opacity: 0.55, child: row) : row;
  }
}

/// The app [id]'s icon, as a button picking another: one of the icons, an
/// image of the user's (PNG), or its own again.
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.app, required this.id});
  final AppController app;
  final String id;

  Future<void> _pick(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final key = await showMenu<String>(
      context: context,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.left, at.bottom + 4, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [_IconGrid(app: app, id: id)],
    );
    switch (key) {
      case null:
        return;
      case '':
        app.setOpenWithIcon(id, null);
      case _IconGrid.image:
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PNG images', extensions: ['png']),
          ],
        );
        if (file != null) {
          app.setOpenWithIcon(id, '$imageIconPrefix${file.path}');
        }
      default:
        app.setOpenWithIcon(id, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Change the icon',
      child: InkWell(
        key: ValueKey('app-icon-$id'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => _pick(context),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child:
              openWithImage(app, id, size: 18) ??
              Icon(openWithIcon(app, id), size: 18, color: AppColors.text),
        ),
      ),
    );
  }
}

/// The icons to pick from, in a grid: the app's own first, the choices,
/// then "PNG image…".
class _IconGrid extends PopupMenuEntry<String> {
  const _IconGrid({required this.app, required this.id});
  final AppController app;
  final String id;

  /// What picking "PNG image…" returns.
  static const image = ':image';

  @override
  double get height => 0;

  @override
  bool represents(String? value) => false;

  @override
  State<_IconGrid> createState() => _IconGridState();
}

class _IconGridState extends State<_IconGrid> {
  @override
  Widget build(BuildContext context) {
    final current = widget.app.settings.openWithIcons[widget.id] ?? '';
    Widget cell(String key, IconData icon, String tooltip) => Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey('icon-choice-$key'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.pop(context, key),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: key == current ? AppColors.selection : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: AppColors.text),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 6 * 38,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                cell('', openWithDefaultIcon(widget.id), 'Its own'),
                for (final MapEntry(:key, :value)
                    in openWithIconChoices.entries)
                  cell(key, value, key),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            key: const ValueKey('icon-choice-image'),
            onPressed: () => Navigator.pop(context, _IconGrid.image),
            icon: const Icon(Icons.image_outlined, size: 16),
            label: const Text('PNG image…'),
          ),
        ],
      ),
    );
  }
}

/// An app to add to the apps to open with: picked among those installed
/// as its name is typed, or a command; and Add.
class _AddAppField extends StatefulWidget {
  const _AddAppField({required this.app});
  final AppController app;

  @override
  State<_AddAppField> createState() => _AddAppFieldState();
}

class _AddAppFieldState extends State<_AddAppField> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  List<InstalledApp> _installed = const [];

  @override
  void initState() {
    super.initState();
    widget.app.installedApps.then((apps) {
      if (mounted) setState(() => _installed = apps);
    });
    // Edited, it may be fine now.
    _c.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Why what was typed couldn't be added, until it changes.
  String? _error;

  /// Adds what was typed: the installed app by that name, if any, else
  /// the command, if it can run.
  void _add() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    final named = _installed
        .where((a) => a.name.toLowerCase() == text.toLowerCase())
        .firstOrNull;
    final command = named?.id ?? text;
    // (An app found installed runs as found.)
    final problem = named == null ? openWithProblem(command) : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    widget.app.addOpenWithApp(command);
    _c.clear();
  }

  Iterable<InstalledApp> _matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final added = widget.app.settings.openWithApps;
    return _installed
        .where((a) => a.name.toLowerCase().contains(q) && !added.contains(a.id))
        // Names starting with it first.
        .toList()
      ..sort(
        (a, b) =>
            (a.name.toLowerCase().startsWith(q) ? 0 : 1) -
            (b.name.toLowerCase().startsWith(q) ? 0 : 1),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(context),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error,
              key: const ValueKey('add-app-error'),
              style: TextStyle(fontSize: 11.5, color: AppColors.danger),
            ),
          ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => RawAutocomplete<InstalledApp>(
              textEditingController: _c,
              focusNode: _focus,
              optionsBuilder: (v) => _matches(v.text),
              displayStringForOption: (a) => a.name,
              onSelected: (a) {
                widget.app.addOpenWithApp(a.id);
                _c.clear();
              },
              fieldViewBuilder: (context, controller, focus, submit) =>
                  TextField(
                    key: const ValueKey('add-app'),
                    controller: controller,
                    focusNode: focus,
                    style: const TextStyle(fontSize: 13),
                    onSubmitted: (_) {
                      submit(); // picks the highlighted suggestion, if any
                      _add();
                    },
                    decoration: InputDecoration(
                      hintText: _installed.isEmpty
                          ? 'subl, idea'
                          : 'Sublime Text, or subl',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: AppColors.textFaint,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
              optionsViewBuilder: (context, select, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: AppColors.panelAlt,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 220,
                      maxWidth: c.maxWidth,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final (i, a) in options.indexed)
                          InkWell(
                            onTap: () => select(a),
                            child: Container(
                              color:
                                  AutocompleteHighlightedOption.of(context) == i
                                  ? AppColors.hover
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                a.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ListenableBuilder(
          listenable: _c,
          builder: (_, _) => FilledButton(
            key: const ValueKey('add-app-confirm'),
            onPressed: _c.text.trim().isEmpty ? null : _add,
            child: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

class _GitPathField extends StatefulWidget {
  const _GitPathField({required this.app});
  final AppController app;

  @override
  State<_GitPathField> createState() => _GitPathFieldState();
}

class _GitPathFieldState extends State<_GitPathField> {
  late final _c = TextEditingController(
    text: widget.app.settings.gitPath ?? '',
  );

  /// What Gutter uses when no path is set (shown as the hint).
  final _defaultPath = GitRunner.resolveGitPath();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        if (!f) widget.app.setGitPath(_c.text);
      },
      child: TextField(
        key: const ValueKey('git-path'),
        controller: _c,
        style: const TextStyle(fontSize: 13),
        onSubmitted: widget.app.setGitPath,
        decoration: InputDecoration(
          hintText: _defaultPath,
          hintStyle: TextStyle(fontSize: 13, color: AppColors.textFaint),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}
