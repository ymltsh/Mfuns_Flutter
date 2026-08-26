import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'playback_log.dart';
import 'playback_state_machine.dart';

/// 可播放的视频控制器抽象（生产实现包装 VideoPlayerController，测试使用替身）。
abstract class VideoPlaybackHandle {
  /// 唯一标识（生产实现基于 controller 的 textureId）。
  String get id;

  bool get isPlaying;
  Duration get position;
  Duration get duration;

  /// 已缓冲的最远位置。
  Duration get buffered;

  double get playbackSpeed;
  double get volume;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
}

/// VideoPlayerController 适配器。
class _VideoControllerHandle implements VideoPlaybackHandle {
  _VideoControllerHandle(this._controller);

  final VideoPlayerController _controller;

  @override
  String get id => 'video#${identityHashCode(_controller)}';

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  Duration get position => _controller.value.position;

  @override
  Duration get duration => _controller.value.duration;

  @override
  Duration get buffered {
    var end = Duration.zero;
    for (final range in _controller.value.buffered) {
      if (range.end > end) end = range.end;
    }
    return end;
  }

  @override
  double get playbackSpeed => _controller.value.playbackSpeed;

  @override
  double get volume => _controller.value.volume;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);
}

/// 后台音频引擎抽象（生产实现基于 just_audio，测试使用替身）。
abstract class BackgroundAudioEngine {
  bool get playing;
  bool get hasSource;
  Duration get position;
  Duration get duration;
  Duration get bufferedPosition;
  double get speed;

  /// 加载音频源；加载完成后调用 [play] 才开始出声。
  Future<void> load(
    String url, {
    Duration? initialPosition,
    double initialPlaybackSpeed = 1.0,
    double volume = 1.0,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 停止并释放当前音频源。
  Future<void> stopSource();
}

/// 生产实现：just_audio（音频专用 ExoPlayer / AVPlayer）。
///
/// - `handleInterruptions: false`：不因系统音频焦点变化自动暂停，
///   规避部分 ROM（尤其 MIUI/HyperOS）退后台时抢占焦点导致后台音频被杀。
/// - 不创建 MediaSession：MediaSession 由 audio_service 统一持有。
class JustAudioBackgroundEngine implements BackgroundAudioEngine {
  JustAudioBackgroundEngine({AudioPlayer? player})
      : _player = player ?? AudioPlayer(handleInterruptions: false);

  final AudioPlayer _player;
  bool _hasSource = false;

  @override
  bool get playing => _player.playing;

  @override
  bool get hasSource => _hasSource;

  @override
  Duration get position =>
      _player.processingState == ProcessingState.idle
          ? Duration.zero
          : _player.position;

  @override
  Duration get duration => _player.duration ?? Duration.zero;

  @override
  Duration get bufferedPosition => _player.bufferedPosition;

  @override
  double get speed => _player.speed;

  @override
  Future<void> load(
    String url, {
    Duration? initialPosition,
    double initialPlaybackSpeed = 1.0,
    double volume = 1.0,
  }) async {
    try {
      await _player.setVolume(volume);
      await _player.setSpeed(initialPlaybackSpeed);
      await _player.setUrl(url, initialPosition: initialPosition);
      _hasSource = true;
    } catch (error) {
      _hasSource = false;
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stopSource() async {
    _hasSource = false;
    try {
      await _player.stop();
    } catch (_) {
      // 引擎已空闲时忽略。
    }
  }
}

/// 媒体状态快照：MediaSession 的唯一状态来源。
class MediaPlaybackSnapshot {
  const MediaPlaybackSnapshot({
    required this.playing,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.speed,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double speed;
}

/// 全局播放协调器（单例）：
///
/// - 全局仲裁：整个 App 同一时间最多一个播放源真正出声。
/// - 单一状态源：MediaSession / 通知栏状态统一从这里读取。
/// - 前后台交接：退后台时把音频从 VideoPlayerController handoff 到
///   just_audio 后台引擎（video_player 的 ExoPlayer 在 Android 上退后台
///   会被插件 `exoPlayer.release()` 整个销毁，无法承担后台播放）。
class MfunsPlaybackCoordinator {
  MfunsPlaybackCoordinator._({required BackgroundAudioEngine backgroundEngine})
      : _bg = backgroundEngine;

  static final MfunsPlaybackCoordinator instance =
      MfunsPlaybackCoordinator._(
    backgroundEngine: JustAudioBackgroundEngine(),
  );

  /// 测试用实例（注入替身引擎）。
  @visibleForTesting
  factory MfunsPlaybackCoordinator.forTest(BackgroundAudioEngine engine) {
    return MfunsPlaybackCoordinator._(backgroundEngine: engine);
  }

  final BackgroundAudioEngine _bg;
  final PlaybackStateMachine _machine = PlaybackStateMachine();

  VideoPlaybackHandle? _bound;
  String? _boundId;
  String? _currentUrl;
  int? _currentPart;
  String? _mediaTitle;
  String? _mediaSubtitle;
  String? _mediaArtUri;

  /// 前后台交接仅对移动端有意义（Android 是必须，iOS 依赖后台音频权限）。
  bool get _canHandoff =>
      debugAllowBackgroundHandoff ??
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// 测试用：覆盖是否允许前后台交接（默认按平台判断）。
  @visibleForTesting
  bool? debugAllowBackgroundHandoff;

  MfunsPlaybackPhase get phase => _machine.phase;

  /// 当前是否存在后台音频会话。
  bool get isBackgroundSourceActive => _machine.backgroundHandoffActive;

  /// 最近一次绑定的媒体元数据（标题/副标题/封面）。
  ({String title, String subtitle, String? artUri})? get currentMediaMeta {
    final title = _mediaTitle;
    if (title == null) return null;
    return (
      title: title,
      subtitle: _mediaSubtitle ?? 'Mfuns 视频',
      artUri: _mediaArtUri,
    );
  }

  /// 页面在 `_select` 成功后绑定当前播放器（同时暂停其他页面的播放器）。
  Future<void> bindVideo(
    VideoPlayerController player, {
    String? url,
    int? part,
    String? title,
    String? subtitle,
    String? artUri,
  }) {
    return bindHandle(
      _VideoControllerHandle(player),
      url: url,
      part: part,
      title: title,
      subtitle: subtitle,
      artUri: artUri,
    );
  }

  /// 解绑播放器；返回是否为当前绑定的播放器（页面据此决定是否 detach 通知）。
  bool unbindVideo(VideoPlayerController player) {
    return unbindHandle(_VideoControllerHandle(player));
  }

  @visibleForTesting
  Future<void> bindHandle(
    VideoPlaybackHandle handle, {
    String? url,
    int? part,
    String? title,
    String? subtitle,
    String? artUri,
  }) async {
    final previous = _bound;
    if (previous != null && _boundId != handle.id) {
      if (previous.isPlaying) {
        PlaybackLog.d('pause other player ${previous.id} before bind');
        try {
          await previous.pause();
        } catch (_) {}
      }
    }
    _bound = handle;
    _boundId = handle.id;
    if (url != null) _currentUrl = url;
    if (part != null) _currentPart = part;
    if (title != null) _mediaTitle = title;
    if (subtitle != null) _mediaSubtitle = subtitle;
    if (artUri != null) _mediaArtUri = artUri;
    _machine.claim(videoPlaying: handle.isPlaying);
    PlaybackLog.d(
      'bind player ${handle.id} url=$_currentUrl part=$_currentPart '
      'phase=${_machine.phase}',
    );
  }

  @visibleForTesting
  bool unbindHandle(VideoPlaybackHandle handle) {
    if (_bound == null || _boundId != handle.id) return false;
    _bound = null;
    _boundId = null;
    _currentUrl = null;
    _currentPart = null;
    _mediaTitle = null;
    _mediaSubtitle = null;
    _mediaArtUri = null;
    _machine.release();
    PlaybackLog.d('unbind player ${handle.id} phase=${_machine.phase}');
    return true;
  }

  /// 播放请求（通知栏 / 页面按钮统一入口）。
  ///
  /// - 后台会话：播放 just_audio 引擎。
  /// - 前台：先 claim（暂停其他页面播放器）再播放当前绑定的视频。
  Future<void> requestPlay() async {
    PlaybackLog.d('play requested phase=${_machine.phase}');
    if (_machine.isBackgroundPhase) {
      if (!_machine.backgroundHandoffActive) return;
      await _bg.play();
      _machine.play();
      PlaybackLog.d('play actual (background engine) phase=${_machine.phase}');
      return;
    }
    final handle = _bound;
    if (handle == null) return;
    await bindHandle(handle);
    await handle.play();
    _machine.play();
    PlaybackLog.d('play actual (video ${handle.id}) phase=${_machine.phase}');
  }

  /// 暂停请求（通知栏 / 页面按钮统一入口）。
  Future<void> requestPause() async {
    PlaybackLog.d('pause requested phase=${_machine.phase}');
    if (_machine.isBackgroundPhase) {
      if (!_machine.backgroundHandoffActive) return;
      await _bg.pause();
      _machine.pause();
      PlaybackLog.d('pause actual (background engine) phase=${_machine.phase}');
      return;
    }
    final handle = _bound;
    if (handle == null) return;
    await handle.pause();
    _machine.pause();
    PlaybackLog.d('pause actual (video ${handle.id}) phase=${_machine.phase}');
  }

  /// 进度拖拽请求（通知栏 seek）。
  Future<void> requestSeek(Duration position) async {
    PlaybackLog.d('seek requested $position phase=${_machine.phase}');
    if (_machine.isBackgroundPhase) {
      if (!_machine.backgroundHandoffActive) return;
      await _bg.seek(position);
      return;
    }
    final handle = _bound;
    if (handle == null) return;
    try {
      await handle.seekTo(position);
    } catch (_) {}
  }

  /// 停止请求（通知栏 stop）：前台→暂停；后台→暂停并释放音频源。
  Future<void> requestStop() async {
    PlaybackLog.d('stop requested phase=${_machine.phase}');
    if (_machine.isBackgroundPhase) {
      if (_machine.backgroundHandoffActive) {
        await _bg.pause();
        await _bg.stopSource();
      }
      _machine.stop();
      PlaybackLog.d('stop actual (background engine) phase=${_machine.phase}');
      return;
    }
    final handle = _bound;
    if (handle != null) {
      try {
        await handle.pause();
      } catch (_) {}
    }
    _machine.stop();
    PlaybackLog.d('stop actual (video) phase=${_machine.phase}');
  }

  /// App 进入后台（由页面 WidgetsBindingObserver 转发）。
  ///
  /// - 后台播放关闭 / 视频未在播 / 接近结尾：暂停视频，不交接。
  /// - 后台播放开启且视频在播：暂停视频 → just_audio 从当前进度续播。
  Future<void> onAppBackgrounded({required bool backgroundPlayEnabled}) async {
    PlaybackLog.d(
      'background enter (backgroundPlay=$backgroundPlayEnabled) '
      'phase=${_machine.phase}',
    );
    if (_machine.isBackgroundPhase) return; // 幂等
    final handle = _bound;
    if (handle == null) {
      _machine.backgroundEnter(handoff: false);
      PlaybackLog.d('background enter no player phase=${_machine.phase}');
      return;
    }
    if (!_canHandoff ||
        !backgroundPlayEnabled ||
        !handle.isPlaying) {
      if (handle.isPlaying) {
        PlaybackLog.d('pause requested (background without handoff)');
        try {
          await handle.pause();
        } catch (_) {}
      }
      _machine.backgroundEnter(handoff: false);
      PlaybackLog.d('background enter paused phase=${_machine.phase}');
      return;
    }
    // 已接近结尾：不交接，保持暂停让自动连播流程处理。
    if (handle.duration > Duration.zero &&
        handle.position >=
            handle.duration - const Duration(seconds: 1)) {
      try {
        await handle.pause();
      } catch (_) {}
      _machine.backgroundEnter(handoff: false);
      PlaybackLog.d('background enter near-end phase=${_machine.phase}');
      return;
    }
    final url = _currentUrl;
    if (url == null || url.isEmpty) {
      try {
        await handle.pause();
      } catch (_) {}
      _machine.backgroundEnter(handoff: false);
      PlaybackLog.d('background enter no url phase=${_machine.phase}');
      return;
    }
    final position = handle.position;
    final speed = handle.playbackSpeed;
    final volume = handle.volume;
    try {
      await handle.pause();
    } catch (_) {}
    _machine.backgroundEnter(handoff: true);
    PlaybackLog.d('background handoff start url=$url pos=$position');
    try {
      await _bg.load(
        url,
        initialPosition: position,
        initialPlaybackSpeed: speed,
        volume: volume,
      );
      await _bg.play();
      _machine.backgroundAudioStarted();
      PlaybackLog.d(
        'background handoff ok phase=${_machine.phase} '
        'bgPlaying=${_bg.playing}',
      );
    } catch (error) {
      // 后台引擎加载/起播失败：保持暂停态并清空 handoff 标记。
      _machine.stop();
      PlaybackLog.d('background handoff FAILED: $error phase=${_machine.phase}');
    }
  }

  /// App 回到前台：把音频从后台引擎切回视频播放器。
  ///
  /// 视频播放器在退后台时其原生 ExoPlayer 可能已被释放，surface 重建后
  /// 才能恢复播放，因此 seek/play 带重试。
  Future<void> onAppForegrounded() async {
    PlaybackLog.d('foreground enter phase=${_machine.phase}');
    if (!_machine.backgroundHandoffActive) return;
    final wasPlaying = _bg.playing;
    final position = _bg.position;
    try {
      await _bg.pause();
      await _bg.stopSource();
    } catch (_) {}
    final handle = _bound;
    var videoPlaying = false;
    if (handle != null) {
      var sought = false;
      for (var attempt = 0; attempt < 15 && !sought; attempt++) {
        try {
          await handle.seekTo(position);
          sought = true;
        } catch (_) {
          // surface 重建前 seek 会失败，等待后重试。
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      PlaybackLog.d(
        'foreground restore seek pos=$position ok=$sought '
        'wasBgPlaying=$wasPlaying',
      );
      if (wasPlaying) {
        try {
          await handle.play();
          videoPlaying = true;
        } catch (_) {
          videoPlaying = false;
        }
      }
    }
    _machine.foregroundEnter(videoPlaying: videoPlaying);
    PlaybackLog.d(
      'foreground enter restored phase=${_machine.phase} '
      'videoPlaying=$videoPlaying',
    );
  }

  /// 当前媒体状态快照（MediaSession 同步用）。
  MediaPlaybackSnapshot? mediaSnapshot() {
    if (_machine.isBackgroundPhase && _machine.backgroundHandoffActive) {
      return MediaPlaybackSnapshot(
        playing: _bg.playing,
        position: _bg.position,
        duration: _bg.duration,
        buffered: _bg.bufferedPosition,
        speed: _bg.speed,
      );
    }
    final handle = _bound;
    if (handle == null) return null;
    return MediaPlaybackSnapshot(
      playing: handle.isPlaying,
      position: handle.position,
      duration: handle.duration,
      buffered: handle.buffered,
      speed: handle.playbackSpeed,
    );
  }
}
