import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../app/zoom.dart';
import '../../git/repository.dart';
import '../dialogs/dialogs.dart';
import '../widgets/common.dart';

/// Repository browser: scanned folders, discovered repos, recents, settings.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.app});
  final AppController app;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _filter = TextEditingController();

  AppController get app => widget.app;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _addScanRoot() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Scan this folder');
    if (dir != null) await app.addScanRoot(dir);
  }

  Future<void> _openRepo() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Open repository');
    if (dir != null) await app.openRepo(dir);
  }

  Future<void> _initRepo() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Initialize here');
    if (dir == null) return;
    try {
      await Repository.init(dir, runner: app.git);
      await app.openRepo(dir);
    } catch (e) {
      app.notify('$e', error: true);
    }
  }

  Future<void> _clone() async {
    final values = await promptFields(
      context,
      title: 'Clone repository',
      confirmLabel: 'Clone',
      fields: [
        const FieldSpec(
          'Repository URL',
          hint: 'git@host:org/repo.git or https://…',
        ),
        FieldSpec(
          'Parent folder',
          initial: app.settings.scanRoots.isEmpty
              ? ''
              : app.settings.scanRoots.first,
        ),
        const FieldSpec(
          'Folder name',
          optional: true,
          hint: 'Defaults to the repository name',
        ),
      ],
    );
    if (values == null) return;
    final url = values[0].trim();
    var name = values[2].trim();
    if (name.isEmpty) {
      name = p.basenameWithoutExtension(
        url.replaceAll(RegExp(r'[/:]+$'), '').split(RegExp(r'[/:]')).last,
      );
    }
    final dest = p.join(values[1].trim(), name);
    app.notify('Cloning $url…');
    try {
      await Repository.clone(url, dest, runner: app.git);
      await app.openRepo(dest);
    } catch (e) {
      app.notify('Clone failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final q = _filter.text.trim().toLowerCase();
        final repos =
            app.settings.knownRepos
                .where((r) => q.isEmpty || r.toLowerCase().contains(q))
                .toList()
              ..sort(
                (a, b) => p
                    .basename(a)
                    .toLowerCase()
                    .compareTo(p.basename(b).toLowerCase()),
              );
        final recents = app.settings.recentRepos.take(8).toList();
        return Container(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 320,
                child: Container(
                  color: AppColors.panel,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Gutter',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ActionButton(
                        icon: Icons.folder_open,
                        label: 'Open repository…',
                        onTap: _openRepo,
                      ),
                      _ActionButton(
                        icon: Icons.travel_explore,
                        label: 'Scan folder for repositories…',
                        onTap: _addScanRoot,
                      ),
                      _ActionButton(
                        icon: Icons.cloud_download_outlined,
                        label: 'Clone…',
                        onTap: _clone,
                      ),
                      _ActionButton(
                        icon: Icons.create_new_folder_outlined,
                        label: 'Init repository…',
                        onTap: _initRepo,
                      ),
                      const SizedBox(height: 20),
                      const _Label('SCANNED FOLDERS'),
                      if (app.settings.scanRoots.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Add a folder to discover every repository inside it.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                      for (final root in app.settings.scanRoots)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.folder,
                                size: 16,
                                color: AppColors.textDim,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Tooltip(
                                  message: root,
                                  child: Text(
                                    root,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ),
                              if (app.scanning.containsKey(root))
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                SmallIconButton(
                                  icon: Icons.refresh,
                                  tooltip: 'Rescan',
                                  onPressed: () => app.scan(root),
                                ),
                              SmallIconButton(
                                icon: Icons.close,
                                tooltip: 'Remove',
                                onPressed: () => app.removeScanRoot(root),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      const _Label('SETTINGS'),
                      _SettingsForm(app: app),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: TextField(
                        controller: _filter,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (repos.isNotEmpty) app.openRepo(repos.first);
                        },
                        decoration: const InputDecoration(
                          hintText: 'Filter repositories…',
                          prefixIcon: Icon(Icons.search, size: 18),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          if (q.isEmpty && recents.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                              child: _Label('RECENT'),
                            ),
                            for (final r in recents)
                              _RepoTile(app: app, path: r),
                            const SizedBox(height: 12),
                          ],
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: _Label('ALL REPOSITORIES (${repos.length})'),
                          ),
                          if (repos.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'No repositories yet. Open one or scan a folder.',
                                style: TextStyle(color: AppColors.textDim),
                              ),
                            ),
                          for (final r in repos) _RepoTile(app: app, path: r),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: AppColors.textDim,
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor: AppColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: AppColors.accent),
      label: Text(label),
    ),
  );
}

class _RepoTile extends StatefulWidget {
  const _RepoTile({required this.app, required this.path});
  final AppController app;
  final String path;

  @override
  State<_RepoTile> createState() => _RepoTileState();
}

class _RepoTileState extends State<_RepoTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.app.tabs.any((t) => t.repo.path == widget.path);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.app.openRepo(widget.path),
        onSecondaryTapUp: (d) => showContextMenu(context, d.globalPosition, [
          menuItem(
            'Open',
            () => widget.app.openRepo(widget.path),
            icon: Icons.open_in_new,
          ),
          menuItem(
            'Show in file manager',
            () => openWithSystem(widget.path),
            icon: Icons.folder_open,
          ),
          menuItem(
            'Copy path',
            () => copyToClipboard(context, widget.path),
            icon: Icons.copy,
          ),
          menuItem(
            'Forget',
            () => widget.app.forgetRepo(widget.path),
            icon: Icons.delete_outline,
            danger: true,
          ),
        ]),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? AppColors.hover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.source_outlined,
                size: 18,
                color: open ? AppColors.accent : AppColors.textDim,
              ),
              const SizedBox(width: 10),
              Text(
                p.basename(widget.path),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.dirname(widget.path),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsForm extends StatelessWidget {
  const _SettingsForm({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          'Zoom',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmallIconButton(
                icon: Icons.remove,
                tooltip: 'Zoom out (Ctrl -)',
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
                tooltip: 'Zoom in (Ctrl +)',
                onPressed: s.zoom < maxZoom ? app.zoomIn : null,
              ),
            ],
          ),
        ),
        _row(
          'Commits loaded',
          AppDropdown<int>(
            value: s.maxCommits,
            items: const [
              (2000, '2,000', null),
              (20000, '20,000', null),
              (100000, '100,000', null),
            ],
            onChanged: app.setMaxCommits,
          ),
        ),
        const SizedBox(height: 8),
        _GitPathField(app: app),
      ],
    );
  }

  Widget _row(String label, Widget control) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        control,
      ],
    ),
  );
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
        controller: _c,
        style: const TextStyle(fontSize: 12.5),
        onSubmitted: widget.app.setGitPath,
        decoration: InputDecoration(
          labelText: 'git executable',
          hintText: widget.app.git.gitPath,
        ),
      ),
    );
  }
}
