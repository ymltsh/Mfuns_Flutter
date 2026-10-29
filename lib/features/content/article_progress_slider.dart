import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 自定义阅读进度滑块启用时，关闭桌面端 MaterialScrollBehavior 自动添加的
/// 垂直 Scrollbar，避免系统滚动条与阅读滑块在文章右侧重复显示。
class ArticleReaderScrollScope extends StatelessWidget {
  const ArticleReaderScrollScope({
    super.key,
    required this.disableAutomaticScrollbar,
    required this.child,
  });

  final bool disableAutomaticScrollbar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!disableAutomaticScrollbar) return child;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }
}

/// 长文章阅读进度滑块：竖向拖拽跳转进度，无操作时自动隐藏。
class ArticleProgressSlider extends StatefulWidget {
  const ArticleProgressSlider({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<ArticleProgressSlider> createState() => _ArticleProgressSliderState();
}

class _ArticleProgressSliderState extends State<ArticleProgressSlider> {
  static const _autoHideDelay = Duration(milliseconds: 2500);
  static const _edgeInset = 14.0;
  static const _thumbHeight = 26.0;
  static const _trackWidth = 4.0;
  static const _hitWidth = 16.0;
  static const _overlayWidth = 88.0;

  Timer? _hideTimer;
  var _visible = false;
  var _dragging = false;
  var _progress = 0.0;

  // 拖拽开始时冻结的滚动范围：文章图片/评论在拖拽过程中异步加载会改变
  // maxScrollExtent，若每次更新都用实时范围换算，内容会相对滑块来回跳动。
  double _dragExtent = 0;

  // 待应用的跳转目标，每帧最多应用一次：高刷新率指针（120Hz+、高回报率
  // 鼠标）每个事件都 jumpTo 会迫使懒加载列表反复重建视口造成抖动。
  double? _pendingJumpTarget;
  var _jumpScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onScrollChanged);
    super.dispose();
  }

  bool get _overflowing =>
      widget.controller.hasClients &&
      widget.controller.position.maxScrollExtent > 0;

  void _onScrollChanged() {
    if (_dragging) return;
    if (!_overflowing) {
      _setVisible(false);
      return;
    }
    final position = widget.controller.position;
    _setProgress(position.pixels / position.maxScrollExtent);
    _setVisible(true);
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    setState(() => _visible = value);
  }

  void _setProgress(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (_progress == clamped) return;
    setState(() => _progress = clamped);
  }

  double _progressFromY(double y, double height) {
    final usable = height - _edgeInset * 2;
    return usable <= 0
        ? 0.0
        : ((y - _edgeInset) / usable).clamp(0.0, 1.0).toDouble();
  }

  void _seekTo(double y, double height) {
    if (!_overflowing) return;
    final progress = _progressFromY(y, height);
    _setProgress(progress);
    final position = widget.controller.position;
    position.jumpTo(progress * position.maxScrollExtent);
  }

  void _startThumbDrag() {
    if (!_overflowing) return;
    _dragExtent = widget.controller.position.maxScrollExtent;
    _pendingJumpTarget = null;
    _hideTimer?.cancel();
    setState(() => _dragging = true);
  }

  void _updateThumbDrag(DragUpdateDetails details, double height) {
    if (!_dragging) return;
    final usable = height - _edgeInset * 2;
    if (usable <= 0) return;
    // DragUpdateDetails.localPosition 以正在移动的拇指自身为坐标系，直接用它
    // 反推轨道位置会在第一帧跳变。增量不受 RenderBox 移动影响，按轨道可用
    // 高度折算即可保持手指与拇指同步。
    final progress = (_progress + details.delta.dy / usable)
        .clamp(0.0, 1.0)
        .toDouble();
    _setProgress(progress);
    _scheduleJump(progress * _dragExtent);
  }

  void _scheduleJump(double target) {
    if (_pendingJumpTarget == target) return;
    _pendingJumpTarget = target;
    if (_jumpScheduled) return;
    _jumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _jumpScheduled = false;
      final pending = _pendingJumpTarget;
      _pendingJumpTarget = null;
      if (pending == null || !mounted || !_overflowing) return;
      final position = widget.controller.position;
      final target = pending.clamp(0.0, position.maxScrollExtent).toDouble();
      if ((position.pixels - target).abs() < 0.5) return;
      position.jumpTo(target);
    });
  }

  void _endThumbDrag() {
    final pending = _pendingJumpTarget;
    _pendingJumpTarget = null;
    if (mounted && pending != null && _overflowing) {
      final position = widget.controller.position;
      final target = pending.clamp(0.0, position.maxScrollExtent).toDouble();
      if ((position.pixels - target).abs() >= 0.5) {
        position.jumpTo(target);
      }
    }
    if (!mounted) return;
    setState(() => _dragging = false);
    // 拖拽期间文章范围可能已变化，结束后以真实位置校正滑块。
    if (_overflowing) {
      final position = widget.controller.position;
      _setProgress(position.pixels / position.maxScrollExtent);
    }
    _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 轨道只响应“点击跳转”，不注册拖动识别器，因此不会与列表滚动手势
    // 竞争；只有拇指（含 8px 外扩命中区）可拖动。此前整条竖带参与拖动
    // 竞技场，滑块可见时会吞掉拇指划动的起始位置，表现为“在段落上滑动
    // 页面卡住”。
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: _overlayWidth,
      child: FractionallySizedBox(
        heightFactor: 0.5,
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !_visible,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = constraints.maxHeight;
                final usable = height - _edgeInset * 2;
                final thumbCenterY = (_edgeInset + _progress * usable)
                    .clamp(_edgeInset, height - _edgeInset)
                    .toDouble();
                final thumbTop = (thumbCenterY - _thumbHeight / 2)
                    .clamp(0.0, height - _thumbHeight)
                    .toDouble();
                final labelTop = (thumbCenterY - 18)
                    .clamp(2.0, height - 38)
                    .toDouble();
                const thumbHitHeight = _thumbHeight + 8;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 轨道：点击跳转进度；不参与拖动，滑动交给列表。
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: _hitWidth,
                      child: GestureDetector(
                        key: const ValueKey('article-progress-track'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _seekTo(details.localPosition.dy, height),
                        child: Stack(
                          children: [
                            Positioned(
                              top: _edgeInset,
                              bottom: _edgeInset,
                              left: (_hitWidth - _trackWidth) / 2,
                              child: Container(
                                width: _trackWidth,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurface.withAlpha(
                                    31,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Positioned(
                              top: _edgeInset,
                              left: (_hitWidth - _trackWidth) / 2,
                              width: _trackWidth,
                              height: _progress * usable,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 拇指：唯一可拖动的部位，保持按下点相对拇指中心的偏移。
                    Positioned(
                      top: thumbTop - 4,
                      right: 0,
                      width: _hitWidth,
                      height: thumbHitHeight,
                      child: GestureDetector(
                        key: const ValueKey('article-progress-thumb-hit'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => _startThumbDrag(),
                        onVerticalDragUpdate: (details) =>
                            _updateThumbDrag(details, height),
                        onVerticalDragEnd: (_) => _endThumbDrag(),
                        onVerticalDragCancel: _endThumbDrag,
                        child: Center(
                          child: Container(
                            key: const ValueKey('article-progress-thumb'),
                            width: 12,
                            height: _thumbHeight,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(64),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_dragging)
                      Positioned(
                        right: 26,
                        top: labelTop,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.inverseSurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              key: const ValueKey('article-progress-label'),
                              '${(_progress * 100).round()}%',
                              style: TextStyle(
                                color: theme.colorScheme.onInverseSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
