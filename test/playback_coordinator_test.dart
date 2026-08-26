import 'package:flutter_test/flutter_test.dart';

import 'package:mfuns_flutter/core/media/playback_coordinator.dart';
import 'package:mfuns_flutter/core/media/playback_state_machine.dart';

class FakeVideoHandle implements VideoPlaybackHandle {
  FakeVideoHandle(this.id);

  @override
  final String id;

  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 5);
  @override
  Duration buffered = const Duration(minutes: 5);
  @override
  double playbackSpeed = 1.0;
  @override
  double volume = 0.7;

  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  bool failSeek = false;
  int seekFailuresRemaining = 0;

  @override
  bool get isPlaying => playing;

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> seekTo(Duration target) async {
    if (failSeek || seekFailuresRemaining > 0) {
      if (seekFailuresRemaining > 0) seekFailuresRemaining--;
      throw StateError('surface not ready');
    }
    seekCalls++;
    position = target;
  }
}
class FakeBackgroundEngine implements BackgroundAudioEngine {
  @override
  bool playing = false;
  @override
  bool hasSource = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 5);
  @override
  Duration bufferedPosition = const Duration(minutes: 5);
  @override
  double speed = 1.0;

  String? loadedUrl;
  Duration? loadedInitialPosition;
  double loadedSpeed = 1.0;
  double loadedVolume = 1.0;
  int loadCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int stopCalls = 0;
  bool failLoad = false;

  @override
  Future<void> load(
    String url, {
    Duration? initialPosition,
    double initialPlaybackSpeed = 1.0,
    double volume = 1.0,
  }) async {
    if (failLoad) throw StateError('load failed');
    loadCalls++;
    loadedUrl = url;
    loadedInitialPosition = initialPosition;
    loadedSpeed = initialPlaybackSpeed;
    loadedVolume = volume;
    hasSource = true;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> seek(Duration target) async {
    seekCalls++;
    position = target;
  }

  @override
  Future<void> stopSource() async {
    stopCalls++;
    hasSource = false;
    position = Duration.zero;
  }
}

void main() {
  group('PlaybackStateMachine', () {
    test('stopped -> claim -> foreground', () {
      final machine = PlaybackStateMachine();
      expect(machine.phase, MfunsPlaybackPhase.stopped);

      machine.claim(videoPlaying: true);
      expect(machine.phase, MfunsPlaybackPhase.foregroundPlaying);

      machine.pause();
      expect(machine.phase, MfunsPlaybackPhase.foregroundPaused);

      machine.play();
      expect(machine.phase, MfunsPlaybackPhase.foregroundPlaying);
    });

    test('claim with paused player lands in foregroundPaused', () {
      final machine = PlaybackStateMachine();
      machine.claim(videoPlaying: false);
      expect(machine.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('release from foreground goes to stopped', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.release();
      expect(machine.phase, MfunsPlaybackPhase.stopped);
      expect(machine.backgroundHandoffActive, isFalse);
    });

    test('backgroundEnter(handoff) -> backgroundPaused -> backgroundAudioStarted', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.backgroundEnter(handoff: true);
      expect(machine.phase, MfunsPlaybackPhase.backgroundPaused);
      expect(machine.backgroundHandoffActive, isTrue);

      machine.backgroundAudioStarted();
      expect(machine.phase, MfunsPlaybackPhase.backgroundPlaying);
    });

    test('background pause/play round trip', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.backgroundEnter(handoff: true);
      machine.backgroundAudioStarted();
      machine.pause();
      expect(machine.phase, MfunsPlaybackPhase.backgroundPaused);
      machine.play();
      expect(machine.phase, MfunsPlaybackPhase.backgroundPlaying);
    });

    test('foregroundEnter after background session restores phase', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.backgroundEnter(handoff: true);
      machine.backgroundAudioStarted();

      machine.foregroundEnter(videoPlaying: true);
      expect(machine.phase, MfunsPlaybackPhase.foregroundPlaying);
      expect(machine.backgroundHandoffActive, isFalse);

      machine.backgroundEnter(handoff: true);
      machine.backgroundAudioStarted();
      machine.foregroundEnter(videoPlaying: false);
      expect(machine.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('source switch round trip', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.sourceSwitchStart();
      expect(machine.phase, MfunsPlaybackPhase.switchingSource);
      machine.sourceSwitchEnd(videoPlaying: true);
      expect(machine.phase, MfunsPlaybackPhase.foregroundPlaying);
    });

    test('illegal transitions throw', () {
      final machine = PlaybackStateMachine();
      expect(() => machine.play(), throwsStateError);
      expect(() => machine.pause(), throwsStateError);
      expect(() => machine.backgroundEnter(handoff: true), throwsStateError);
      expect(() => machine.sourceSwitchStart(), throwsStateError);
      expect(() => machine.sourceSwitchEnd(videoPlaying: true), throwsStateError);

      final bg = PlaybackStateMachine()..claim(videoPlaying: true);
      bg.backgroundEnter(handoff: true);
      expect(() => bg.claim(videoPlaying: true), throwsStateError);
      expect(() => bg.sourceSwitchStart(), throwsStateError);
      expect(() => bg.backgroundEnter(handoff: true), throwsStateError);
    });

    test('stop clears background session', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.backgroundEnter(handoff: true);
      machine.backgroundAudioStarted();
      machine.stop();
      expect(machine.backgroundHandoffActive, isFalse);
      expect(machine.phase, MfunsPlaybackPhase.backgroundPaused);

      final fg = PlaybackStateMachine()..claim(videoPlaying: true);
      fg.stop();
      expect(fg.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('play/pause are idempotent in same-phase', () {
      final machine = PlaybackStateMachine()..claim(videoPlaying: true);
      machine.play();
      machine.play();
      expect(machine.phase, MfunsPlaybackPhase.foregroundPlaying);
      machine.pause();
      machine.pause();
      expect(machine.phase, MfunsPlaybackPhase.foregroundPaused);
    });
  });

  group('MfunsPlaybackCoordinator', () {
    late FakeBackgroundEngine bg;
    late MfunsPlaybackCoordinator coordinator;

    setUp(() {
      bg = FakeBackgroundEngine();
      coordinator = MfunsPlaybackCoordinator.forTest(bg)
        ..debugAllowBackgroundHandoff = true;
    });

    test('bind pauses a previously playing player (A/B 互斥)', () async {
      final a = FakeVideoHandle('a')..playing = true;
      final b = FakeVideoHandle('b');

      await coordinator.bindHandle(a);
      expect(a.playing, isTrue);
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPlaying);

      await coordinator.bindHandle(b);
      expect(a.playing, isFalse, reason: '绑定 B 时 A 必须暂停');
      expect(b.playing, isFalse);
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('unbind returns false for non-bound player', () async {
      final a = FakeVideoHandle('a');
      final b = FakeVideoHandle('b');
      await coordinator.bindHandle(a);
      expect(coordinator.unbindHandle(b), isFalse);
      expect(coordinator.unbindHandle(a), isTrue);
      expect(coordinator.phase, MfunsPlaybackPhase.stopped);
    });

    test('requestPlay / requestPause drive the bound video player', () async {
      final a = FakeVideoHandle('a');
      await coordinator.bindHandle(a);

      await coordinator.requestPlay();
      expect(a.playing, isTrue);
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPlaying);

      await coordinator.requestPause();
      expect(a.playing, isFalse);
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('requestSeek forwards to the video player', () async {
      final a = FakeVideoHandle('a');
      await coordinator.bindHandle(a);
      await coordinator.requestSeek(const Duration(seconds: 30));
      expect(a.position, const Duration(seconds: 30));
    });

    test('背景播放关闭时退后台只暂停视频，不交接', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a);

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: false);
      expect(a.playing, isFalse);
      expect(bg.hasSource, isFalse);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPaused);
      expect(coordinator.isBackgroundSourceActive, isFalse);
    });

    test('视频未播放时退后台不交接', () async {
      final a = FakeVideoHandle('a');
      await coordinator.bindHandle(a);

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(bg.hasSource, isFalse);
      expect(coordinator.isBackgroundSourceActive, isFalse);
    });

    test('后台播放开启且视频在播时 handoff 到后台引擎', () async {
      final a = FakeVideoHandle('a')
        ..playing = true
        ..position = const Duration(seconds: 42)
        ..playbackSpeed = 1.5
        ..volume = 0.6;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4', part: 3);

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(a.playing, isFalse, reason: '视频必须暂停');
      expect(bg.hasSource, isTrue);
      expect(bg.loadedUrl, 'https://example.com/v.mp4');
      expect(bg.loadedInitialPosition, const Duration(seconds: 42));
      expect(bg.loadedSpeed, 1.5);
      expect(bg.loadedVolume, 0.6);
      expect(bg.playing, isTrue);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPlaying);
      expect(coordinator.isBackgroundSourceActive, isTrue);
    });

    test('handoff 失败时回退为后台暂停态', () async {
      bg.failLoad = true;
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPaused);
      expect(coordinator.isBackgroundSourceActive, isFalse);
      expect(a.playing, isFalse);
    });

    test('接近结尾的视频不交接', () async {
      final a = FakeVideoHandle('a')
        ..playing = true
        ..position = const Duration(minutes: 4, seconds: 59)
        ..duration = const Duration(minutes: 5);
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(bg.hasSource, isFalse);
      expect(coordinator.isBackgroundSourceActive, isFalse);
    });

    test('通知栏后台暂停/恢复', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(bg.playing, isTrue);

      await coordinator.requestPause();
      expect(bg.playing, isFalse);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPaused);

      await coordinator.requestPlay();
      expect(bg.playing, isTrue);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPlaying);
    });

    test('通知栏后台 seek 转发到后台引擎', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);

      await coordinator.requestSeek(const Duration(seconds: 90));
      expect(bg.position, const Duration(seconds: 90));
    });

    test('回前台把音频切回视频播放器', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      bg.position = const Duration(seconds: 60);
      bg.playing = true;

      await coordinator.onAppForegrounded();
      expect(bg.hasSource, isFalse, reason: '后台源必须释放');
      expect(bg.playing, isFalse);
      expect(a.position, const Duration(seconds: 60), reason: '视频进度同步后台进度');
      expect(a.playing, isTrue, reason: '后台在播则恢复视频');
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPlaying);
      expect(coordinator.isBackgroundSourceActive, isFalse);
    });

    test('后台暂停时回前台，视频保持暂停', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      await coordinator.requestPause();
      bg.position = const Duration(seconds: 10);

      await coordinator.onAppForegrounded();
      expect(a.playing, isFalse);
      expect(a.position, const Duration(seconds: 10));
      expect(coordinator.phase, MfunsPlaybackPhase.foregroundPaused);
    });

    test('回前台 seek 失败时重试直到成功', () async {
      final a = FakeVideoHandle('a')
        ..playing = true
        ..seekFailuresRemaining = 2;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      bg.position = const Duration(seconds: 30);

      await coordinator.onAppForegrounded();
      expect(a.seekCalls, 1, reason: '前两次失败后第三次成功');
      expect(a.position, const Duration(seconds: 30));
      expect(a.playing, isTrue);
    });

    test('requestStop 清空后台会话', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(coordinator.isBackgroundSourceActive, isTrue);

      await coordinator.requestStop();
      expect(bg.playing, isFalse);
      expect(bg.hasSource, isFalse);
      expect(coordinator.isBackgroundSourceActive, isFalse);
      expect(coordinator.phase, MfunsPlaybackPhase.backgroundPaused);
    });

    test('mediaSnapshot 反映后台引擎状态', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      final foreground = coordinator.mediaSnapshot();
      expect(foreground, isNotNull);
      expect(foreground!.playing, isTrue);

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      bg.position = const Duration(seconds: 5);
      final background = coordinator.mediaSnapshot();
      expect(background!.playing, isTrue);
      expect(background.position, const Duration(seconds: 5));
    });

    test('二次退后台幂等（不重复交接）', () async {
      final a = FakeVideoHandle('a')..playing = true;
      await coordinator.bindHandle(a, url: 'https://example.com/v.mp4');
      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      final loadsAfterFirst = bg.loadCalls;

      await coordinator.onAppBackgrounded(backgroundPlayEnabled: true);
      expect(bg.loadCalls, loadsAfterFirst);
    });
  });
}
