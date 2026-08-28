/// 播放生命周期阶段（单一状态源，与具体播放引擎解耦）。
///
/// 期望的状态迁移：
/// - stopped --claim--> foregroundPlaying / foregroundPaused
/// - foreground* --backgroundEnter--> backgroundPaused --backgroundAudioStarted--> backgroundPlaying
/// - background* --foregroundEnter--> foregroundPlaying / foregroundPaused
/// - foregroundPlaying <-> foregroundPaused（用户/通知栏暂停与恢复）
/// - backgroundPlaying <-> backgroundPaused（通知栏暂停与恢复）
/// - foreground* --sourceSwitchStart--> switchingSource --sourceSwitchEnd--> foreground*
class MfunsPlaybackPhase {
  const MfunsPlaybackPhase._(this.name);

  /// 无绑定播放器。
  static const stopped = MfunsPlaybackPhase._('stopped');

  /// 前台视频播放中。
  static const foregroundPlaying = MfunsPlaybackPhase._('foregroundPlaying');

  /// 前台视频已暂停。
  static const foregroundPaused = MfunsPlaybackPhase._('foregroundPaused');

  /// 后台音频播放中（已 handoff 到后台引擎）。
  static const backgroundPlaying = MfunsPlaybackPhase._('backgroundPlaying');

  /// 后台音频已暂停。
  static const backgroundPaused = MfunsPlaybackPhase._('backgroundPaused');

  /// 清晰度/分P 切换中。
  static const switchingSource = MfunsPlaybackPhase._('switchingSource');

  final String name;

  bool get isBackground =>
      identical(this, backgroundPlaying) || identical(this, backgroundPaused);

  bool get isForeground =>
      identical(this, foregroundPlaying) || identical(this, foregroundPaused);

  @override
  String toString() => name;
}

/// 播放状态机：校验所有阶段迁移合法性。
///
/// 纯 Dart、无任何 Flutter/平台依赖，便于单元测试。
class PlaybackStateMachine {
  PlaybackStateMachine({MfunsPlaybackPhase phase = MfunsPlaybackPhase.stopped})
      : _phase = phase;

  MfunsPlaybackPhase _phase;

  /// 是否存在后台音频会话（handoff 未结束）。
  bool backgroundHandoffActive = false;

  MfunsPlaybackPhase get phase => _phase;

  bool get isBackgroundPhase => _phase.isBackground;

  bool get isForegroundPhase => _phase.isForeground;

  /// 绑定/替换当前播放器（页面 `_select` 成功或点击播放前）。
  void claim({required bool videoPlaying}) {
    if (_phase.isBackground) {
      throw StateError('claim from ${_phase.name}');
    }
    _phase = videoPlaying
        ? MfunsPlaybackPhase.foregroundPlaying
        : MfunsPlaybackPhase.foregroundPaused;
  }

  /// 解绑播放器（页面销毁 / 播放器被替换）。
  void release() {
    if (_phase.isBackground) {
      // 正常情况下后台会话期间页面不会销毁；若发生则同时丢弃后台会话。
      backgroundHandoffActive = false;
    }
    _phase = MfunsPlaybackPhase.stopped;
  }

  /// 请求播放（前台视频或后台引擎）。
  void play() {
    switch (_phase) {
      case MfunsPlaybackPhase.foregroundPaused:
        _phase = MfunsPlaybackPhase.foregroundPlaying;
        return;
      case MfunsPlaybackPhase.backgroundPaused:
        _phase = MfunsPlaybackPhase.backgroundPlaying;
        return;
      case MfunsPlaybackPhase.foregroundPlaying:
      case MfunsPlaybackPhase.backgroundPlaying:
        return; // 幂等
      case MfunsPlaybackPhase.stopped:
      case MfunsPlaybackPhase.switchingSource:
        throw StateError('play from ${_phase.name}');
    }
  }

  /// 请求暂停（前台视频或后台引擎）。
  void pause() {
    switch (_phase) {
      case MfunsPlaybackPhase.foregroundPlaying:
        _phase = MfunsPlaybackPhase.foregroundPaused;
        return;
      case MfunsPlaybackPhase.backgroundPlaying:
        _phase = MfunsPlaybackPhase.backgroundPaused;
        return;
      case MfunsPlaybackPhase.foregroundPaused:
      case MfunsPlaybackPhase.backgroundPaused:
        return; // 幂等
      case MfunsPlaybackPhase.stopped:
      case MfunsPlaybackPhase.switchingSource:
        throw StateError('pause from ${_phase.name}');
    }
  }

  /// 进入后台。
  ///
  /// [handoff] 为 true 表示音频已（或将要）交接给后台引擎；交接引擎
  /// 尚未真正出声前统一记为 backgroundPaused，由 [backgroundAudioStarted]
  /// 在后台引擎 `play()` 成功后迁移到 backgroundPlaying。
  void backgroundEnter({required bool handoff}) {
    if (_phase == MfunsPlaybackPhase.stopped ||
        _phase == MfunsPlaybackPhase.switchingSource ||
        _phase.isBackground) {
      throw StateError('backgroundEnter from ${_phase.name}');
    }
    backgroundHandoffActive = handoff;
    _phase = MfunsPlaybackPhase.backgroundPaused;
  }

  /// 后台引擎真正开始出声（handoff 后 `bg.play()` 成功）。
  void backgroundAudioStarted() {
    if (_phase != MfunsPlaybackPhase.backgroundPaused) {
      throw StateError('backgroundAudioStarted from ${_phase.name}');
    }
    _phase = MfunsPlaybackPhase.backgroundPlaying;
  }

  /// 回到前台，[videoPlaying] 表示是否恢复视频播放。
  void foregroundEnter({required bool videoPlaying}) {
    backgroundHandoffActive = false;
    _phase = videoPlaying
        ? MfunsPlaybackPhase.foregroundPlaying
        : MfunsPlaybackPhase.foregroundPaused;
  }

  /// 清晰度/分P 切换开始（仅前台合法）。
  void sourceSwitchStart() {
    if (!_phase.isForeground) {
      throw StateError('sourceSwitchStart from ${_phase.name}');
    }
    _phase = MfunsPlaybackPhase.switchingSource;
  }

  /// 清晰度/分P 切换结束。
  void sourceSwitchEnd({required bool videoPlaying}) {
    if (_phase != MfunsPlaybackPhase.switchingSource) {
      throw StateError('sourceSwitchEnd from ${_phase.name}');
    }
    _phase = videoPlaying
        ? MfunsPlaybackPhase.foregroundPlaying
        : MfunsPlaybackPhase.foregroundPaused;
  }

  /// 通知栏 stop：前台→暂停；后台→清空后台会话。
  void stop() {
    if (_phase.isBackground) {
      backgroundHandoffActive = false;
      _phase = MfunsPlaybackPhase.backgroundPaused;
      return;
    }
    if (_phase == MfunsPlaybackPhase.foregroundPlaying ||
        _phase == MfunsPlaybackPhase.switchingSource) {
      _phase = MfunsPlaybackPhase.foregroundPaused;
    }
  }
}
