import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:video_player/video_player.dart';

import 'playback_coordinator.dart';
import 'playback_log.dart';

/// 媒体播放通知（Android MediaSession / iOS 控制中心）：
/// 视频播放时绑定当前播放器，在系统通知栏展示标题/封面与
/// 播放、暂停、进度拖拽等媒体控制，并随播放状态实时同步。
///
/// 所有播放/暂停/seek 操作都转发给 [MfunsPlaybackCoordinator]，
/// 由协调器决定目标引擎（前台 = 视频播放器，后台 = just_audio 引擎），
/// 避免出现“MediaSession 状态”与“实际发声引擎”两套状态源。
class MfunsAudioHandler extends BaseAudioHandler {
  MfunsAudioHandler._();

  static final MfunsAudioHandler instance = MfunsAudioHandler._();

  Timer? _syncTimer;
  bool? _lastPlaying;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration? _lastDuration;
  String? _lastTitle;
  String? _lastSubtitle;
  String? _lastArtUri;

  /// 绑定当前播放的视频控制器并显示媒体通知；重复调用会切换绑定。
  Future<void> attach({
    required VideoPlayerController player,
    required String title,
    required String subtitle,
    String? artUri,
    String? url,
    int? part,
  }) async {
    try {
      _syncTimer?.cancel();
      _lastTitle = title;
      _lastSubtitle = subtitle;
      _lastArtUri = artUri;
      await MfunsPlaybackCoordinator.instance.bindVideo(
        player,
        url: url,
        part: part,
        title: title,
        subtitle: subtitle,
        artUri: artUri,
      );
      _pushMediaItem(
        title: title,
        subtitle: subtitle,
        artUri: artUri,
        duration: player.value.duration,
      );
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
      playbackState.add(PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      ));
    } catch (_) {
      // 静默。
    }
  }

  /// 页面点击播放后，若通知已被 detach（例如返回上一页），重新挂起通知。
  Future<void> reAttachIfNeeded() async {
    try {
      if (mediaItem.value != null) return;
      final meta = MfunsPlaybackCoordinator.instance.currentMediaMeta;
      if (meta == null) return;
      _lastTitle = meta.title;
      _lastSubtitle = meta.subtitle;
      _lastArtUri = meta.artUri;
      _pushMediaItem(
        title: meta.title,
        subtitle: meta.subtitle,
        artUri: meta.artUri,
        duration: _lastDuration ?? Duration.zero,
      );
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _sync();
      });
      _sync(force: true);
    } catch (_) {
      // 静默。
    }
  }

  void _pushMediaItem({
    required String title,
    required String subtitle,
    String? artUri,
    Duration duration = Duration.zero,
  }) {
    mediaItem.add(MediaItem(
      id: 'mfuns-video',
      title: title,
      artist: subtitle,
      album: 'Mfuns',
      artUri: artUri == null || artUri.isEmpty ? null : Uri.parse(artUri),
      duration: duration,
    ));
  }

  /// 播放/暂停/进度变化时更新通知状态；播放状态切换立即同步，
  /// 常规进度最多每 500ms 上报一次，避免过度刷新 MediaSession。
  void _sync({bool force = false}) {
    final snapshot = MfunsPlaybackCoordinator.instance.mediaSnapshot();
    if (snapshot == null) return;
    if (snapshot.duration != _lastDuration) {
      _lastDuration = snapshot.duration;
      _pushMediaItem(
        title: _lastTitle ?? 'Mfuns 视频',
        subtitle: _lastSubtitle ?? 'Mfuns 视频',
        artUri: _lastArtUri,
        duration: snapshot.duration,
      );
    }
    final now = DateTime.now();
    if (!force &&
        snapshot.playing == _lastPlaying &&
        now.difference(_lastSync).inMilliseconds < 500) {
      return;
    }
    _lastPlaying = snapshot.playing;
    _lastSync = now;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (snapshot.playing) MediaControl.pause else MediaControl.play,
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
      playing: snapshot.playing,
      updatePosition: snapshot.position,
      bufferedPosition: snapshot.buffered,
      speed: snapshot.speed,
    ));
  }

  @override
  Future<void> play() async {
    PlaybackLog.d('play requested (notification)');
    final coordinator = MfunsPlaybackCoordinator.instance;
    await coordinator.requestPlay();
    await reAttachIfNeeded();
    _sync(force: true);
    PlaybackLog.d(
      'audio handler state: playing=${coordinator.mediaSnapshot()?.playing} '
      'phase=${coordinator.phase}',
    );
  }

  @override
  Future<void> pause() async {
    PlaybackLog.d('pause requested (notification)');
    final coordinator = MfunsPlaybackCoordinator.instance;
    await coordinator.requestPause();
    _sync(force: true);
    PlaybackLog.d(
      'audio handler state: playing=${coordinator.mediaSnapshot()?.playing} '
      'phase=${coordinator.phase}',
    );
  }

  @override
  Future<void> seek(Duration position) async {
    await MfunsPlaybackCoordinator.instance.requestSeek(position);
    _sync(force: true);
  }

  @override
  Future<void> stop() async {
    PlaybackLog.d('stop requested (notification)');
    await MfunsPlaybackCoordinator.instance.requestStop();
    await detach();
  }

  /// 通知栏“下一首”作为快进 10 秒使用。
  @override
  Future<void> skipToNext() async {
    final snapshot = MfunsPlaybackCoordinator.instance.mediaSnapshot();
    if (snapshot == null) return;
    await MfunsPlaybackCoordinator.instance
        .requestSeek(snapshot.position + const Duration(seconds: 10));
    _sync(force: true);
  }

  /// 通知栏“上一首”作为快退 10 秒使用。
  @override
  Future<void> skipToPrevious() async {
    final snapshot = MfunsPlaybackCoordinator.instance.mediaSnapshot();
    if (snapshot == null) return;
    var target = snapshot.position - const Duration(seconds: 10);
    if (target < Duration.zero) target = Duration.zero;
    await MfunsPlaybackCoordinator.instance.requestSeek(target);
    _sync(force: true);
  }
}
