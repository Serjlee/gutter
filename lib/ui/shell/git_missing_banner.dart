import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../git/git_runner.dart';
import '../widgets/common.dart';

/// Shown on the home tab while git doesn't run: why, and how to get it.
/// Gutter checks again when its window gets focus back (from installing
/// it, say), or on "Check again".
class GitMissingBanner extends StatefulWidget {
  const GitMissingBanner({super.key, required this.app, this.platform});
  final AppController app;

  /// 'windows', 'macos' or 'linux'; this system's when null (for tests).
  final String? platform;

  @override
  State<GitMissingBanner> createState() => _GitMissingBannerState();
}

class _GitMissingBannerState extends State<GitMissingBanner> {
  bool _checking = false;

  AppController get app => widget.app;

  String get _platform =>
      widget.platform ??
      (Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'linux');

  Future<void> _check() async {
    setState(() => _checking = true);
    await app.checkGit();
    if (mounted) setState(() => _checking = false);
  }

  /// Starts [exe] for the user to follow (an installer, a console).
  Future<void> _start(String exe, List<String> args, String started) async {
    try {
      await Process.start(exe, args, mode: ProcessStartMode.detached);
      app.notify(started);
    } catch (e) {
      app.notify('Couldn\'t start $exe: download git instead.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final problem = app.gitProblem;
    if (problem == null) return const SizedBox.shrink();
    final missing = problem.startsWith('Gutter can\'t find git');
    final (String hint, Widget? install) = switch (_platform) {
      'windows' => (
        'Windows doesn\'t come with git: install Git for Windows (with its '
            'credential manager, for signing in to GitHub and others).',
        FilledButton.icon(
          key: const ValueKey('git-install'),
          // winget comes with Windows 10 and 11; in a console of its own,
          // so its progress (and the installer's prompts) show.
          onPressed: () => _start(
            'cmd.exe',
            [
              '/c',
              'start',
              'winget',
              'install',
              '--id',
              'Git.Git',
              '-e',
              '--source',
              'winget',
            ],
            'Installing Git in a new window. Gutter checks again when '
                'you\'re back.',
          ),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Install Git'),
        ),
      ),
      'macos' => (
        'macOS installs git with Apple\'s command line tools (or use '
            'Homebrew\'s: `brew install git`).',
        FilledButton.icon(
          key: const ValueKey('git-install'),
          onPressed: () => _start('xcode-select', [
            '--install',
          ], 'Follow the installer. Gutter checks again when you\'re back.'),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Install command line tools'),
        ),
      ),
      _ => (
        '${GitRunner.inFlatpak ? 'The Flatpak runs your system\'s git. ' : ''}'
            'Install it with your package manager, e.g. '
            '`sudo apt install git` or `sudo dnf install git`.',
        null,
      ),
    };
    return Container(
      key: const ValueKey('git-missing'),
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 20, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  missing ? 'Git isn\'t installed' : 'Gutter can\'t run git',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  missing ? hint : problem,
                  style: TextStyle(fontSize: 13, color: AppColors.textDim),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ?install,
                    OutlinedButton(
                      onPressed: () =>
                          openWithSystem('https://git-scm.com/downloads'),
                      child: const Text('Download'),
                    ),
                    TextButton(
                      key: const ValueKey('git-check'),
                      onPressed: _checking ? null : _check,
                      child: Text(_checking ? 'Checking…' : 'Check again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
