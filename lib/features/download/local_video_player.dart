import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

/// 本地视频播放器：直接复用线上播放器全屏控件（[VideoDetailPage] 横屏层）
/// 的 UI / 交互骨架，裁剪掉弹幕、清晰度切换、后台播放交接、媒体通知等
/// 网络播放专属能力，只服务已下载完成的本地文件；多分P任务可在播放器内
/// 像在线播放一样切换分P（顶部 P 菜单）。
///
/// 复用的交互骨架：
/// - 单击显隐控制层，4 秒无操作自动隐藏（播放中）
/// - 双击左右半屏 ±10 秒、长按 2× 倍速
/// - 左右拖动比例式跳转进度
/// - 左半屏上下滑动调亮度、右半屏调音量（带 HUD 反馈）
/// - 顶部返回 + 标题 + 分P菜单，底部时间 + 进度滑杆 + 全屏退出
/// - 设置面板：音量滑杆 + 倍速选择
/// - 移动端进入横屏沉浸式（immersiveSticky），桌面端窗口级全屏
class LocalVideoPlayer extends StatefulWidget {
  const LocalVideoPlayer({
    super.key,
    required this.title,
    required this.parts,
    this.initialPart,
  });

  final String title;

  /// 可播放的分P文件：分P序号 → 本地文件路径（已完成的分P）。
  final Map<int, String> parts;

  /// 初始播放的分P；null 时取 [parts] 的第一个。
  final int? initialPart;

  @override
  State<LocalVideoPlayer> createState() => _LocalVideoPlayerState();
}

/// 桌面端支持窗口级全屏（Windows/macOS/Linux），移动端与 Web 不适用。
final bool _isDesktop =
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class _LocalVideoPlayerState extends State<LocalVideoPlayer> {
  VideoPlayerController? _player;
  late int _currentPart;
  var _controlsVisible = true;
  var _showOptions = false;
  var _switchingPart = false;
  var _isSeeking = false;
  var _isLongPressSpeed = false;
  String? _seekNotice;
  _SlideFeedback? _slideFeedback;
  Timer? _hideTimer;
  Timer? _ticker;
  double _doubleTapX = 0;
  double _dragSeekStartDx = 0;
  Duration _dragSeekBase = Duration.zero;
  double _volume = .7;
  var _brightness = .5;
  var _brightnessAvailable = true;
  String? _error;
  var _initialized = false;

  /// 分P序号（升序）。
  List<int> get _partOrder =>
      (widget.parts.keys.toList()..sort());

  @override
  void initState() {
    super.initState();
    _currentPart =
        widget.initialPart ?? _partOrder.firstOrNull ?? 1;
    _init();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 桌面端（Windows/macOS/Linux）把窗口切入真全屏，移动端只旋转方向。
    if (_isDesktop) {
      windowManager.setFullScreen(true).catchError((_) {});
    }
    _scheduleHide();
    _ticker = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted && _player?.value.isPlaying == true) {
        setState(() {});
      }
    });
    _loadBrightness();
  }

  Future<void> _init() => _openPart(_currentPart, autoplay: true);

  /// 打开指定分P的本地文件（切换分P时重建播放器）。
  Future<void> _openPart(int part, {required bool autoplay}) async {
    final path = widget.parts[part];
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() => _error = '本地文件不存在：P$part');
      }
      return;
    }
    final old = _player;
    _player = null;
    setState(() {
      _switchingPart = true;
      _error = null;
      _initialized = false;
    });
    await old?.dispose();
    final controller = VideoPlayerController.file(File(path));
    _player = controller;
    try {
      await controller.initialize();
      await controller.setVolume(_volume);
      if (autoplay) await controller.play();
      if (!mounted) return;
      setState(() {
        _currentPart = part;
        _initialized = true;
        _switchingPart = false;
        _controlsVisible = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _initialized = false;
          _switchingPart = false;
          _error = '本地视频打开失败：$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ticker?.cancel();
    _player?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (_isDesktop) {
      windowManager.setFullScreen(false).catchError((_) {});
    }
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = value.clamp(0.0, 1.0).toDouble());
      }
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _handleVerticalSlide(
      DragUpdateDetails details, double width, double height) {
    final delta = -details.delta.dy / height;
    if (details.localPosition.dx < width / 2 && _brightnessAvailable) {
      final next = (_brightness + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _brightness = next;
        _slideFeedback = _SlideFeedback(brightness: true, value: next);
        _controlsVisible = true;
      });
      _setBrightness(next);
    } else {
      final next = (_volume + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _volume = next;
        _slideFeedback = _SlideFeedback(brightness: false, value: next);
        _controlsVisible = true;
      });
      _player?.setVolume(next);
    }
    _scheduleHide();
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _clearSlideFeedback() => setState(() => _slideFeedback = null);

  Future<void> _setLongPressSpeed(bool active) async {
    if (_isLongPressSpeed == active) return;
    setState(() => _isLongPressSpeed = active);
    await _player?.setPlaybackSpeed(active ? 2 : 1);
  }

  Future<void> _seekBy(int seconds) async {
    final player = _player;
    if (player == null) return;
    var target = player.value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > player.value.duration) target = player.value.duration;
    await player.seekTo(target);
    if (mounted) {
      setState(() {
        _controlsVisible = true;
        _seekNotice = '${seconds > 0 ? '+' : ''}$seconds 秒';
      });
      _scheduleHide();
    }
  }

  /// 左右拖动调整进度：记录按下时的播放位置，随横向位移比例式拖动。
  void _startDragSeek(DragStartDetails details) {
    final player = _player;
    if (player == null) return;
    _dragSeekStartDx = details.globalPosition.dx;
    _dragSeekBase = player.value.position;
    setState(() => _isSeeking = true);
  }

  void _finishDragSeek() => setState(() => _isSeeking = false);

  void _updateDragSeek(DragUpdateDetails details) {
    final player = _player;
    if (player == null) return;
    final duration = player.value.duration;
    if (duration <= Duration.zero) return;
    final width = MediaQuery.sizeOf(context).width;
    final deltaDx = details.globalPosition.dx - _dragSeekStartDx;
    final target = _dragSeekBase +
        Duration(
            milliseconds:
                (deltaDx / width * duration.inMilliseconds).round());
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > duration) clamped = duration;
    player.seekTo(clamped);
    if (mounted) {
      setState(() {
        _seekNotice =
            '${_formatDuration(clamped)} / ${_formatDuration(duration)}';
        _controlsVisible = true;
      });
      _scheduleHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final player = _player;
    if (!_initialized || player == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 14),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _controlsVisible = !_controlsVisible);
          if (_controlsVisible) _scheduleHide();
        },
        onDoubleTapDown: (details) => _doubleTapX = details.localPosition.dx,
        onDoubleTap: () {
          final width = MediaQuery.sizeOf(context).width;
          _seekBy(_doubleTapX < width / 2 ? -10 : 10);
        },
        onLongPressStart: (_) => _setLongPressSpeed(true),
        onLongPressEnd: (_) => _setLongPressSpeed(false),
        onLongPressCancel: () => _setLongPressSpeed(false),
        onHorizontalDragStart: _startDragSeek,
        onHorizontalDragUpdate: _updateDragSeek,
        onHorizontalDragEnd: (_) => _finishDragSeek(),
        onHorizontalDragCancel: _finishDragSeek,
        onVerticalDragUpdate: (details) => _handleVerticalSlide(
            details,
            MediaQuery.sizeOf(context).width,
            MediaQuery.sizeOf(context).height),
        onVerticalDragEnd: (_) => _clearSlideFeedback(),
        onVerticalDragCancel: _clearSlideFeedback,
        child: _switchingPart
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: player,
          builder: (context, value, _) {
            final duration = value.duration;
            final position = value.position;
            return Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio:
                        value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                    child: VideoPlayer(player),
                  ),
                ),
                if (_controlsVisible)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x99000000),
                            Colors.transparent,
                            Color(0xaa000000)
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            child: SafeArea(
                              bottom: false,
                              child: Row(
                                children: [
                                  IconButton(
                                    color: Colors.white,
                                    tooltip: '退出',
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    onPressed: _close,
                                  ),
                                  Expanded(
                                    child: Text(widget.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  if (widget.parts.length > 1)
                                    PopupMenuButton<int>(
                                      tooltip: '分 P',
                                      initialValue: _currentPart,
                                      onSelected: (part) {
                                        if (part == _currentPart) return;
                                        _openPart(part, autoplay: true);
                                      },
                                      itemBuilder: (context) => _partOrder
                                          .map((part) => PopupMenuItem(
                                                value: part,
                                                child: Text('P$part'),
                                              ))
                                          .toList(),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 8),
                                        child: Text(
                                          'P$_currentPart',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ),
                                  IconButton(
                                    color: Colors.white,
                                    tooltip: '播放器设置',
                                    onPressed: () => setState(
                                        () => _showOptions = !_showOptions),
                                    icon: const Icon(
                                        Icons.settings_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showOptions)
                            Positioned(
                              top: 58,
                              right: 16,
                              child: _LocalPlayerOptionsPanel(
                                volume: _volume,
                                onVolumeChanged: (next) async {
                                  setState(() => _volume = next);
                                  await player.setVolume(next);
                                },
                                onSpeedChanged: (next) async {
                                  await player.setPlaybackSpeed(next);
                                },
                              ),
                            ),
                          Center(
                            child: _isSeeking || value.isBuffering
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      foregroundColor: Colors.white,
                                    ),
                                    iconSize: 54,
                                    onPressed: () async {
                                      if (value.isPlaying) {
                                        await player.pause();
                                      } else {
                                        await player.play();
                                      }
                                      _scheduleHide();
                                    },
                                    icon: Icon(value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                                  ),
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 4,
                            child: SafeArea(
                              top: false,
                              child: Row(
                                children: [
                                  Text(_formatDuration(position),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11)),
                                  Expanded(
                                    child: Slider(
                                      activeColor: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      inactiveColor: Colors.white38,
                                      value: duration.inMilliseconds == 0
                                          ? 0
                                          : position.inMilliseconds
                                              .clamp(0,
                                                  duration.inMilliseconds)
                                              .toDouble(),
                                      max: duration.inMilliseconds == 0
                                          ? 1
                                          : duration.inMilliseconds.toDouble(),
                                      onChanged: (milliseconds) {
                                        player.seekTo(Duration(
                                            milliseconds:
                                                milliseconds.round()));
                                        _scheduleHide();
                                      },
                                      onChangeStart: (_) => setState(
                                          () => _isSeeking = true),
                                      onChangeEnd: (_) => setState(
                                          () => _isSeeking = false),
                                    ),
                                  ),
                                  Text(_formatDuration(duration),
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11)),
                                  IconButton(
                                    color: Colors.white,
                                    icon: const Icon(
                                        Icons.fullscreen_exit_rounded),
                                    onPressed: _close,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_slideFeedback != null)
                  IgnorePointer(
                    child:
                        _VerticalSlideFeedback(feedback: _slideFeedback!),
                  ),
                if (_seekNotice != null && _controlsVisible)
                  // 位于中央播放/暂停按钮下方，避免重叠。
                  Align(
                    alignment: const Alignment(0, 0.38),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Text(_seekNotice!,
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                if (_isLongPressSpeed)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Text('2.0× 倍速播放',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 滑动反馈 HUD：亮度 / 音量。
class _SlideFeedback {
  const _SlideFeedback({required this.brightness, required this.value});

  final bool brightness;
  final double value;
}

class _VerticalSlideFeedback extends StatelessWidget {
  const _VerticalSlideFeedback({required this.feedback});

  final _SlideFeedback feedback;

  @override
  Widget build(BuildContext context) => Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  feedback.brightness
                      ? Icons.brightness_6_rounded
                      : feedback.value == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(height: 7),
                Text(
                  '${feedback.brightness ? '亮度' : '音量'} ${(feedback.value * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 设置面板（裁剪自全屏设置面板）：音量滑杆 + 倍速选择。
class _LocalPlayerOptionsPanel extends StatelessWidget {
  const _LocalPlayerOptionsPanel({
    required this.volume,
    required this.onVolumeChanged,
    required this.onSpeedChanged,
  });

  final double volume;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedChanged;

  @override
  Widget build(BuildContext context) => Container(
        width: 248,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xee1d1d23),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_rounded,
                    color: Colors.white, size: 19),
                Expanded(
                  child: Slider(
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Colors.white38,
                    value: volume,
                    onChanged: onVolumeChanged,
                  ),
                ),
                PopupMenuButton<double>(
                  initialValue: 1.0,
                  onSelected: onSpeedChanged,
                  itemBuilder: (context) => [
                    for (final option in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(value: option, child: Text('${option}x')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('1.0x',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

String _formatDuration(Duration value) {
  final hours = value.inHours.toString().padLeft(2, '0');
  final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return value.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
