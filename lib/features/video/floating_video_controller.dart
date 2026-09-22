import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/media_notification.dart';
import '../../core/media/playback_coordinator.dart';
import '../home/home_repository.dart';

class FloatingVideoSession {
  const FloatingVideoSession({
    required this.player,
    required this.preview,
    required this.quality,
  });

  final VideoPlayerController player;
  final ContentPreview preview;
  final VideoQuality quality;
}

/// 在线播放器在详情页、应用内小窗和系统 PiP 之间的共享会话。
///
/// 普通详情页仍拥有播放器；只有切换到应用内小窗时，本控制器才接管销毁责任。
class FloatingVideoController extends ChangeNotifier {
  FloatingVideoController._();

  static final FloatingVideoController instance = FloatingVideoController._();

  FloatingVideoSession? _session;
  bool _floating = false;
  bool _ownsPlayer = false;

  FloatingVideoSession? get session => _session;
  VideoPlayerController? get player => _session?.player;
  bool get isFloating => _floating && _session != null;

  void attach(FloatingVideoSession session) {
    final old = _session?.player;
    if (identical(old, session.player)) {
      _session = session;
      notifyListeners();
      return;
    }
    old?.removeListener(_onPlayerChanged);
    _session = session;
    _floating = false;
    _ownsPlayer = false;
    session.player.addListener(_onPlayerChanged);
    notifyListeners();
  }

  /// 把详情页播放器交给全局悬浮层，随后详情路由即可安全销毁。
  bool startFloating(VideoPlayerController player) {
    if (!identical(_session?.player, player)) return false;
    _floating = true;
    _ownsPlayer = true;
    notifyListeners();
    return true;
  }

  /// 重新打开同一详情页时归还播放器，保留进度与播放状态。
  FloatingVideoSession? takeFor(int videoId) {
    final current = _session;
    if (!_ownsPlayer || current?.preview.id != videoId) return null;
    _floating = false;
    _ownsPlayer = false;
    notifyListeners();
    return current;
  }

  bool owns(VideoPlayerController player) =>
      _ownsPlayer && identical(_session?.player, player);

  void detach(VideoPlayerController player) {
    if (!identical(_session?.player, player) || _ownsPlayer) return;
    player.removeListener(_onPlayerChanged);
    _session = null;
    _floating = false;
    notifyListeners();
  }

  Future<void> close() async {
    final current = _session;
    if (current == null) return;
    current.player.removeListener(_onPlayerChanged);
    _session = null;
    final shouldDispose = _ownsPlayer;
    _floating = false;
    _ownsPlayer = false;
    notifyListeners();
    if (!shouldDispose) return;
    MfunsPlaybackCoordinator.instance.unbindVideo(current.player);
    try {
      await current.player.pause();
    } catch (_) {}
    await current.player.dispose();
    MfunsAudioHandler.instance.detach();
  }

  void _onPlayerChanged() => notifyListeners();
}
