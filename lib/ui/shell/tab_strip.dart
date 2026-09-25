import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../repo/repo_tab_controller.dart';

class TabStrip extends StatelessWidget {
  const TabStrip({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: AppColors.background,
      child: Row(
        children: [
          _HomeTab(
            active: app.activeIndex == -1,
            onTap: () => app.activate(-1),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: app.tabs.length,
              onReorderItem: app.moveTab,
              proxyDecorator: (child, _, _) =>
                  Material(color: Colors.transparent, child: child),
              itemBuilder: (context, i) {
                final tab = app.tabs[i];
                return ReorderableDragStartListener(
                  key: ObjectKey(tab),
                  index: i,
                  child: _RepoTab(
                    tab: tab,
                    active: app.activeIndex == i,
                    onTap: () => app.activate(i),
                    onClose: () => app.closeTab(i),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Repositories (Ctrl+T)',
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.toolbar : null,
            border: const Border(right: BorderSide(color: AppColors.border)),
          ),
          child: Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: active ? AppColors.accent : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

class _RepoTab extends StatefulWidget {
  const _RepoTab({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final RepoTabController tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_RepoTab> createState() => _RepoTabState();
}

class _RepoTabState extends State<_RepoTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tab,
      builder: (context, _) {
        final tab = widget.tab;
        final working = tab.busy != null || tab.fetching || tab.loading;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kMiddleMouseButton) widget.onClose();
            },
            child: GestureDetector(
              onTap: widget.onTap,
              child: Tooltip(
                message: tab.repo.path,
                waitDuration: const Duration(seconds: 1),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    maxWidth: 220,
                  ),
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    color: widget.active
                        ? AppColors.toolbar
                        : (_hover ? AppColors.hover : null),
                    border: Border(
                      right: const BorderSide(color: AppColors.border),
                      top: BorderSide(
                        color: widget.active
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  // The minimum width can exceed a short name's: keep the
                  // close button at the right edge anyway.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (working)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              )
                            else if (tab.operation.name != 'none')
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.warning_amber,
                                  size: 13,
                                  color: AppColors.warning,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                tab.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: widget.active
                                      ? AppColors.text
                                      : AppColors.textDim,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 22,
                        child: (_hover || widget.active)
                            ? InkWell(
                                onTap: widget.onClose,
                                borderRadius: BorderRadius.circular(3),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppColors.textDim,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
