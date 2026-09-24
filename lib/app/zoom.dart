import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

const minZoom = 0.5;
const maxZoom = 3.0;
const zoomStep = 0.1;

double clampZoom(double z) =>
    (z.clamp(minZoom, maxZoom) * 100).roundToDouble() / 100;

bool get isZoomModifierPressed {
  final k = HardwareKeyboard.instance;
  return k.isControlPressed || k.isMetaPressed;
}

/// Scales the whole UI by [zoom]: the child is laid out at `size / zoom`
/// and painted scaled up, so everything (text, custom painters, hit
/// testing, overlays) scales uniformly and stays vector-crisp.
class ZoomScope extends StatefulWidget {
  const ZoomScope({
    super.key,
    required this.zoom,
    required this.onZoomChanged,
    required this.child,
  });

  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final Widget child;

  @override
  State<ZoomScope> createState() => _ZoomScopeState();
}

class _ZoomScopeState extends State<ZoomScope> {
  bool _showBadge = false;
  Timer? _badgeTimer;

  @override
  void didUpdateWidget(ZoomScope old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      _badgeTimer?.cancel();
      _showBadge = true;
      _badgeTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _showBadge = false);
      });
    }
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !isZoomModifierPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final dy = (e as PointerScrollEvent).scrollDelta.dy;
      if (dy == 0) return;
      widget.onZoomChanged(
        clampZoom(widget.zoom + (dy < 0 ? zoomStep : -zoomStep)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.zoom;
    final mq = MediaQuery.of(context);
    final inner = ScrollConfiguration(
      behavior: const _ZoomAwareScrollBehavior(),
      child: widget.child,
    );
    Widget content = inner;
    if (zoom != 1.0) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth / zoom;
          final h = constraints.maxHeight / zoom;
          return ClipRect(
            child: Transform.scale(
              scale: zoom,
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: w,
                maxWidth: w,
                minHeight: h,
                maxHeight: h,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(w, h),
                    padding: mq.padding / zoom,
                    viewPadding: mq.viewPadding / zoom,
                    viewInsets: mq.viewInsets / zoom,
                  ),
                  child: inner,
                ),
              ),
            ),
          );
        },
      );
    }
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          Positioned.fill(child: content),
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showBadge ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    key: const ValueKey('zoom-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.toolbar.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${(zoom * 100).round()}%',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollables ignore wheel events while Ctrl/Cmd is held, so the wheel
/// zooms instead of scrolling.
class _ZoomAwareScrollBehavior extends MaterialScrollBehavior {
  const _ZoomAwareScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _ZoomAwarePhysics(parent: super.getScrollPhysics(context));
}

class _ZoomAwarePhysics extends ScrollPhysics {
  const _ZoomAwarePhysics({super.parent});

  @override
  _ZoomAwarePhysics applyTo(ScrollPhysics? ancestor) =>
      _ZoomAwarePhysics(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !isZoomModifierPressed && super.shouldAcceptUserOffset(position);
}
