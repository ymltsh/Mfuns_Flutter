import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:video_player/video_player.dart';

/// 媒体播放通知（Android MediaSession / iOS 控制中心）：
/// 视频播放时绑定当前播放器，在系统通知栏展示标题/封面与
/// 播放、暂停、进度拖拽等媒体控制，并随播放状态实时同步。
class MfunsAudioHandler extends BaseAudioHandler {
  MfunsAudioHandler._();

  static final MfunsAudioHandler instance = MfunsAudioHandler._();

  VideoPlayerController? _player;
  Timer? _syncTimer;
  bool? _lastPlaying;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  /// 绑定当前播放的视频控制器并显示媒体通知；重复调用会切换绑定。
  Future<void> attach({
    required VideoPlayerController player,
    required String title,
    required String subtitle,
    String? artUri,
  }) async {
    try {
      _syncTimer?.cancel();
      _player = player;
      mediaItem.add(MediaItem(
        id: 'mfuns-video',
        title: title,
        artist: subtitle,
        album: 'Mfuns',
        artUri: artUri == null || artUri.isEmpty ? null : Uri.parse(artUri),
        duration: player.value.duration,
      ));
      _lastPlaying = player.value.isPlaying;
      _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
      // 周期同步进度/播放状态；processingState 非 idle 时前台服务与通知自动常驻。
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _sync();
      });
      _sync(force: true);
    } catch (_) {
      // 媒体通知失败不影响视频播放本身。
    }
  }

  /// 解绑播放器并移除媒体通知（进入 idle 状态后服务与通知自动停止）。
  Future<void> detach() async {
    try {
      _syncTimer?.cancel();
      _syncTimer = null;
      _player = null;
      playbackState.add(PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      ));
    } catch (_) {
      // 静默。
    }
  }

  /// 播放/暂停/进度变化时更新通知状态；播放状态切换立即同步，
  /// 常规进度最多每 500ms 上报一次，避免过度刷新 MediaSession。
  void _sync({bool force = false}) {
    final player = _player;
    if (player == null) return;
    final playing = player.value.isPlaying;
    final now = DateTime.now();
    if (!force &&
        playing == _lastPlaying &&
        now.difference(_lastSync).inMilliseconds < 500) {
      return;
    }
    _lastPlaying = playing;
    _lastSync = now;
    playbackState.add(_playbackState());
  }

  PlaybackState _playbackState() {
    final player = _player;
    final playing = player?.value.isPlaying ?? false;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: player?.value.position ?? Duration.zero,
      bufferedPosition: _bufferedEnd(player?.value.buffered ?? const []),
      speed: player?.value.playbackSpeed ?? 1.0,
    );
  }

  Duration _bufferedEnd(List<DurationRange> ranges) {
    var end = Duration.zero;
    for (final range in ranges) {
      if (range.end > end) end = range.end;
    }
    return end;
  }

  @override
  Future<void> play() async {
    await _player?.play();
    _sync(force: true);
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    _sync(force: true);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seekTo(position);
    _sync(force: true);
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
    detach();
  }

  /// 通知栏“下一首”作为快进 10 秒使用。
  @override
  Future<void> skipToNext() async {
    final player = _player;
    if (player == null) return;
    await player.seekTo(player.value.position + const Duration(seconds: 10));
    _sync(force: true);
  }

  /// 通知栏“上一首”作为快退 10 秒使用。
  @override
  Future<void> skipToPrevious() async {
    final player = _player;
    if (player == null) return;
    var target = player.value.position - const Duration(seconds: 10);
    if (target < Duration.zero) target = Duration.zero;
    await player.seekTo(target);
    _sync(force: true);
  }
}
