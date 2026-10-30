import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/settings_store.dart' show GraphMode;
import '../../app/theme.dart';
import '../../app/zoom.dart';
import '../../git/git_runner.dart';
import '../../graph/graph_painter.dart';
import '../widgets/common.dart';
import 'dialogs.dart';

/// The settings, in a dialog: from the home tab, with ⌘, (macOS) or
/// Ctrl+P, or from the app menu on macOS.
Future<void> showSettingsDialog(BuildContext context, AppController app) =>
    showAppDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        // Held at the top: switching sections changes its height.
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
        child: SizedBox(width: 600, child: _SettingsPanel(app: app)),
      ),
    );

enum SettingsSection {
  appearance('Appearance', Icons.palette_outlined),
  git('Git', Icons.call_split),
  performance('Performance', Icons.speed);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The sections as a toolbar of tabs on top (as macOS apps' settings
/// have them), the current one's settings, and Done.
class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({required this.app});
  final AppController app;

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  var _section = SettingsSection.appearance;
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
            // Always shown when there is more: easy to miss otherwise.
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: ListenableBuilder(
                  listenable: widget.app,
                  builder: (_, _) =>
                      SettingsForm(app: widget.app, section: _section),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
            subtitle: 'Empty: the one Gutter finds, shown faded',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rows in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _Group(rows),
          ),
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
  const _Row(this.label, {this.subtitle, this.info, this.control, this.below});
  final String label;
  final String? subtitle;
  final String? info;
  final Widget? control;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textDim,
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
