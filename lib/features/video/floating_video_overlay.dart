import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/playback_coordinator.dart';
import 'floating_video_controller.dart';

class FloatingVideoOverlay extends StatefulWidget {
  const FloatingVideoOverlay({
    super.key,
    required this.onExpand,
    this.bottom = 12,
    this.controlsHideDelay = const Duration(seconds: 3),
  });

  final VoidCallback onExpand;
  final double bottom;
  final Duration controlsHideDelay;

  @override
  State<FloatingVideoOverlay> createState() => _FloatingVideoOverlayState();
}

class _FloatingVideoOverlayState extends State<FloatingVideoOverlay> {
  Offset _offset = Offset.zero;
  Timer? _controlsTimer;
  bool _showControls = true;
  bool _wasFloating = false;

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }

  void _syncFloatingState(bool floating) {
    if (floating == _wasFloating) return;
    _wasFloating = floating;
    _controlsTimer?.cancel();
    _showControls = true;
    if (floating) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(widget.controlsHideDelay, () {
      if (!mounted || !_wasFloating || !_showControls) return;
      setState(() => _showControls = false);
    });
  }

  void _showControlsTemporarily() {
    if (!_showControls) setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  void _handleSurfaceTap() {
    if (_showControls) {
      _controlsTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      _showControlsTemporarily();
    }
  }

  Future<void> _togglePlayback(bool isPlaying) async {
    _showControlsTemporarily();
    if (isPlaying) {
      await MfunsPlaybackCoordinator.instance.requestPause();
    } else {
      await MfunsPlaybackCoordinator.instance.requestPlay();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: FloatingVideoController.instance,
    builder: (context, _) {
      final controller = FloatingVideoController.instance;
      final player = controller.player;
      final floating = controller.isFloating && player != null;
      _syncFloatingState(floating);
      if (!floating) {
        return const SizedBox.shrink();
      }
      final width = (MediaQuery.sizeOf(context).width * .48)
          .clamp(180.0, 280.0)
          .toDouble();
      return Positioned(
        right: 12 - _offset.dx,
        bottom: widget.bottom - _offset.dy,
        child: GestureDetector(
          key: const ValueKey('floating-video-player'),
          onTap: _handleSurfaceTap,
          onPanStart: (_) => _showControlsTemporarily(),
          onPanUpdate: (details) => setState(() {
            _offset += details.delta;
            final size = MediaQuery.sizeOf(context);
            _offset = Offset(
              _offset.dx.clamp(-(size.width - width - 24), 0).toDouble(),
              _offset.dy
                  .clamp(-(size.height - width * 9 / 16 - 40), 0)
                  .toDouble(),
            );
          }),
          onPanEnd: (_) => _scheduleControlsHide(),
          onPanCancel: _scheduleControlsHide,
          child: Material(
            elevation: 16,
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: width * 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: player.value.size.width,
                      height: player.value.size.height,
                      child: VideoPlayer(player),
                    ),
                  ),
                  AnimatedOpacity(
                    key: const ValueKey('floating-video-controls'),
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x66000000),
                              Color(0x11000000),
                              Color(0x77000000),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 2,
                              right: 2,
                              child: IconButton(
                                tooltip: '关闭小窗',
                                color: Colors.white,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black45,
                                ),
                                onPressed: controller.close,
                                icon: const Icon(Icons.close_rounded, size: 19),
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: IconButton.filledTonal(
                                tooltip: player.value.isPlaying ? '暂停' : '播放',
                                onPressed: () =>
                                    _togglePlayback(player.value.isPlaying),
                                icon: Icon(
                                  player.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 2,
                              bottom: 2,
                              child: IconButton(
                                tooltip: '展开播放器',
                                color: Colors.white,
                                onPressed: widget.onExpand,
                                icon: const Icon(
                                  Icons.open_in_full_rounded,
                                  size: 19,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 系统 PiP 模式下的极简根布局，只展示视频画面。
///
/// [child] 必须始终留在组件树中，否则切换 PiP 时 Navigator 会被卸载，
/// 当前视频详情页和它持有的播放器也会随之销毁。
class SystemPipLayout extends StatelessWidget {
  const SystemPipLayout({
    super.key,
    required this.active,
    required this.video,
    required this.child,
  });

  final bool active;
  final Widget video;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (active)
        Positioned.fill(
          child: ColoredBox(color: Colors.black, child: video),
        ),
    ],
  );
}

/// 系统 PiP 模式下的极简视频画面。
class SystemPipVideoSurface extends StatelessWidget {
  const SystemPipVideoSurface({super.key, required this.player});

  final VideoPlayerController player;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: AspectRatio(
        aspectRatio: player.value.aspectRatio == 0
            ? 16 / 9
            : player.value.aspectRatio,
        child: VideoPlayer(player),
      ),
    ),
  );
}
