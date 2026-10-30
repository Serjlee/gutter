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
      builder: (ctx) => AlertDialog(
        title: const Text('Settings', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: app,
              builder: (_, _) => SettingsForm(app: app),
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('settings-close'),
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: AppColors.textDim,
      ),
    ),
  );
}

/// The settings, in sections.
class SettingsForm extends StatelessWidget {
  const SettingsForm({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('APPEARANCE'),
        _row(
          'Theme',
          AppDropdown<String>(
            key: const ValueKey('theme-mode'),
            value: s.themeMode,
            items: const [
              ('system', 'System', null),
              ('light', 'Light', null),
              ('dark', 'Dark', null),
            ],
            onChanged: app.setThemeMode,
          ),
        ),
        _row(
          'Graph',
          AppDropdown<GraphMode>(
            key: const ValueKey('graph-mode'),
            value: s.graphMode,
            items: const [
              (GraphMode.full, 'Full', null),
              (GraphMode.compact, 'Compact', null),
              (GraphMode.fork, 'Fork', null),
              (GraphMode.alignedFork, 'Aligned Fork', null),
            ],
            preview: _GraphModePreview.new,
            onChanged: app.setGraphMode,
          ),
          info:
              'Where the graph puts branch and tag labels.\n\n'
              'Full: in a column of their own.\n'
              'Compact: in the graph column, past the lanes.\n'
              'Fork: before the message, right after each commit\'s lanes.\n'
              'Aligned Fork: before the message, with messages in a column.',
        ),
        _current(
          const ValueKey('graph-mode-preview'),
          _GraphModePreview(s.graphMode),
        ),
        _row(
          'Line hint',
          AppDropdown<LineHint>(
            key: const ValueKey('line-hint'),
            value: s.lineHint,
            items: const [
              (LineHint.fade, 'Fade', null),
              (LineHint.leader, 'Leader line', null),
              (LineHint.line, 'Line', null),
              (LineHint.none, 'None', null),
            ],
            preview: _LineHintPreview.new,
            onChanged: app.setLineHint,
          ),
          info:
              'What links each commit in the graph to its message, in its '
              'branch\'s color.',
        ),
        _current(
          const ValueKey('line-hint-preview'),
          _LineHintPreview(s.lineHint),
        ),
        _row(
          'Zoom',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmallIconButton(
                icon: Icons.remove,
                tooltip: 'Zoom out (${shortcut('-')})',
                onPressed: s.zoom > minZoom ? app.zoomOut : null,
              ),
              SizedBox(
                width: 46,
                child: InkWell(
                  onTap: app.zoomReset,
                  child: Text(
                    '${(s.zoom * 100).round()}%',
                    key: const ValueKey('zoom-value'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              SmallIconButton(
                icon: Icons.add,
                tooltip: 'Zoom in (${shortcut('+')})',
                onPressed: s.zoom < maxZoom ? app.zoomIn : null,
              ),
            ],
          ),
        ),
        _row(
          'Syntax highlighting',
          AppDropdown<bool>(
            key: const ValueKey('syntax-highlighting'),
            value: s.syntaxHighlight,
            items: const [(true, 'On', null), (false, 'Off', null)],
            onChanged: app.setSyntaxHighlight,
          ),
          info:
              'Colors code in diffs, file previews and conflicts, for about '
              '40 languages (by file extension). Very large files stay '
              'plain.',
        ),
        _row(
          'GitHub avatars',
          AppDropdown<bool>(
            key: const ValueKey('github-avatars'),
            value: s.githubAvatars,
            items: const [(true, 'On', null), (false, 'Off', null)],
            onChanged: app.setGithubAvatars,
          ),
          info:
              'For repositories on GitHub, shows the authors\' GitHub '
              'profile pictures instead of their initials.\n\n'
              'Gutter asks GitHub\'s avatar server for each author\'s '
              'picture by commit email (no API calls), as they come into '
              'view. Authors whose email isn\'t on a GitHub account keep '
              'their initials.',
        ),
        const SizedBox(height: 20),
        const _Label('GIT'),
        _row('Git executable', _GitPathField(app: app), expand: true),
        _row(
          'Auto-fetch',
          AppDropdown<int>(
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
        _row(
          'Force tag fetch',
          AppDropdown<bool>(
            key: const ValueKey('force-tag-fetch'),
            value: s.forceTagFetch,
            items: const [(false, 'Ask', null), (true, 'Always', null)],
            onChanged: app.setForceTagFetch,
          ),
          info:
              'When a tag moved on the remote (deploy tags like "dev" or '
              '"staging" often do), git won\'t move your local one.\n\n'
              'Ask: Gutter lists the moved tags and offers Force Tag Fetch, '
              'which replaces your local tags with the remote\'s.\n\n'
              'Always: every fetch does that, without asking.',
        ),
        const SizedBox(height: 20),
        const _Label('HISTORY'),
        _row(
          'Commits loaded',
          AppDropdown<int>(
            value: s.maxCommits,
            items: const [
              (2000, '2,000', null),
              (20000, '20,000', null),
              (100000, '100,000', null),
              (0, 'All', null),
            ],
            onChanged: app.setMaxCommits,
          ),
          info:
              'How many commits a repository loads when it opens. '
              'Scrolling to the bottom of the graph loads the next batch '
              'of the same size, so older history is always reachable.\n\n'
              'All loads the whole history at once: simplest, but slower '
              'to open very large repositories.\n\n'
              'Applies to repositories opened from now on.',
        ),
      ],
    );
  }

  /// What the current choice looks like, under its row's control.
  Widget _current(Key key, Widget preview) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: preview,
      ),
    ),
  );

  /// A label and its control; with [expand] the control takes the rest of
  /// the row (text fields) instead of the label. [info] adds an info icon
  /// after the label that explains the setting (hover or click).
  Widget _row(
    String label,
    Widget control, {
    bool expand = false,
    String? info,
  }) {
    final text = Text(label, style: const TextStyle(fontSize: 13));
    final labelWidget = info == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              const SizedBox(width: 4),
              _InfoIcon(message: info, label: label),
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (expand) ...[
            labelWidget,
            const SizedBox(width: 12),
            Expanded(child: control),
          ] else ...[
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: labelWidget),
            ),
            control,
          ],
        ],
      ),
    );
  }
}

/// Three graph rows laid out as [mode] does it, as a sample.
class _GraphModePreview extends StatelessWidget {
  const _GraphModePreview(this.mode);
  final GraphMode mode;

  static const _rowH = 22.0;
  static const _labelsW = 46.0; // Full: their column
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
    final graphW = _lanesEnd(2) + (mode == GraphMode.compact ? _room : 0) + 6;
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
      height: _rowH * rows.length,
      child: Stack(
        children: [
          Positioned(
            left: graphX,
            top: 0,
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
                    top: i * _rowH + 3.5,
                    child: pill(label, color),
                  ),
                Positioned(
                  left: graphX + graphW,
                  top: i * _rowH,
                  height: _rowH,
                  child: Center(child: Text(msg, style: text)),
                ),
              ],
              GraphMode.compact => [
                if (label != null)
                  Positioned(
                    left: _lanesEnd(lanes) + 2,
                    top: i * _rowH + 3.5,
                    child: pill(label, color),
                  ),
                Positioned(
                  left: graphW,
                  top: i * _rowH,
                  height: _rowH,
                  child: Center(child: Text(msg, style: text)),
                ),
              ],
              GraphMode.fork || GraphMode.alignedFork => [
                Positioned(
                  left: mode == GraphMode.fork ? _lanesEnd(lanes) + 4 : graphW,
                  top: i * _rowH,
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
    final text = TextStyle(fontSize: 12, color: AppColors.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (lane, message) in [
          (0, 'Merge branch \'feature\''),
          (1, 'Add the login form'),
        ])
          SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(64, 24),
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

/// Current build and the latest release, with a link when an update exists.
