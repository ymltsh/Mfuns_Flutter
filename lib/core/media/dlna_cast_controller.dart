import 'dart:async';
import 'dart:io';

import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DlnaRenderer {
  const DlnaRenderer._(this.device);

  final DLNADevice device;
  String get name => device.info.friendlyName;
  String get id => '${device.info.URLBase}|$name';
}

/// 一次投屏会话中的单个分 P 播放源。
class DlnaCastPart {
  const DlnaCastPart({
    required this.part,
    required this.url,
    this.duration = Duration.zero,
  });

  final int part;
  final String url;
  final Duration duration;
}

/// Android 在线视频 DLNA 控制器：设备发现和远端播放状态都集中在此处，
/// 页面只负责选择设备与呈现遥控器。
class DlnaCastController extends ChangeNotifier {
  DlnaCastController._();

  static final DlnaCastController instance = DlnaCastController._();
  static const _multicast = MethodChannel('mfuns/dlna_multicast');

  DLNAManager? _manager;
  StreamSubscription<Map<String, DLNADevice>>? _deviceSubscription;
  StreamSubscription<PositionParser>? _positionSubscription;
  List<DlnaRenderer> _devices = const [];
  DlnaRenderer? _connected;
  bool _discovering = false;
  bool _connecting = false;
  bool _playing = false;
  String? _error;
  String _title = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _volume = 70;
  List<DlnaCastPart> _parts = const [];
  int? _currentPart;
  bool _switchingPart = false;
  bool _refreshing = false;
  DateTime? _ignoreCompletionUntil;
  Timer? _autoNextTimer;

  List<DlnaRenderer> get devices => _devices;
  DlnaRenderer? get connected => _connected;
  bool get isDiscovering => _discovering;
  bool get isConnecting => _connecting;
  bool get isConnected => _connected != null;
  bool get isPlaying => _playing;
  String? get error => _error;
  String get title => _title;
  Duration get position => _position;
  Duration get duration => _duration;
  int get volume => _volume;
  List<DlnaCastPart> get parts => _parts;
  int? get currentPart => _currentPart;
  bool get isSwitchingPart => _switchingPart;
  bool get isRefreshing => _refreshing;
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> startDiscovery() async {
    if (!isSupported || _discovering) return;
    _discovering = true;
    _error = null;
    _devices = const [];
    notifyListeners();
    try {
      await _multicast.invokeMethod<void>('acquire');
      final manager = _manager ??= DLNAManager();
      final deviceManager = await manager.start(reusePort: true);
      await _deviceSubscription?.cancel();
      _deviceSubscription = deviceManager.devices.stream.listen(
        (items) {
          final seen = <String>{};
          _devices =
              items.values
                  .map(DlnaRenderer._)
                  .where((item) => seen.add(item.id))
                  .toList(growable: false)
                ..sort((a, b) => a.name.compareTo(b.name));
          notifyListeners();
        },
        onError: (Object error) {
          _error = '搜索投屏设备失败：$error';
          notifyListeners();
        },
      );
    } catch (error) {
      _error = '无法启动 DLNA 搜索，请确认手机已连接 Wi-Fi';
      _discovering = false;
      notifyListeners();
    }
  }

  Future<void> stopDiscovery() async {
    _discovering = false;
    await _deviceSubscription?.cancel();
    _deviceSubscription = null;
    _manager?.stop();
    _manager = null;
    if (isSupported) {
      try {
        await _multicast.invokeMethod<void>('release');
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<bool> cast({
    required DlnaRenderer renderer,
    required List<DlnaCastPart> parts,
    required int initialPart,
    required String title,
    required Duration position,
  }) async {
    if (_connecting) return false;
    final initial = parts.cast<DlnaCastPart?>().firstWhere(
      (item) => item?.part == initialPart,
      orElse: () => null,
    );
    if (initial == null) return false;
    _connecting = true;
    _error = null;
    notifyListeners();
    try {
      await renderer.device.setUrl(
        initial.url,
        title: _partTitle(title, initial.part, parts.length),
        type: VideoMime.any,
      );
      if (position > Duration.zero) {
        await renderer.device.seek(PositionParser.toStr(position.inSeconds));
      }
      await renderer.device.play();
      await stopDiscovery();
      _connected = renderer;
      _title = title;
      _parts = List.unmodifiable(
        parts.toList()..sort((a, b) => a.part.compareTo(b.part)),
      );
      _currentPart = initial.part;
      _position = position;
      _duration = initial.duration;
      _playing = true;
      _ignoreCompletionUntil = DateTime.now().add(const Duration(seconds: 2));
      await _positionSubscription?.cancel();
      _positionSubscription = renderer.device.currPosition.stream.listen((
        value,
      ) {
        final reportedPosition = Duration(seconds: value.RelTimeInt);
        final ignoreUntil = _ignoreCompletionUntil;
        final resetAtEnd =
            reportedPosition == Duration.zero &&
            _position > Duration.zero &&
            _duration > Duration.zero &&
            _position >= _duration - const Duration(seconds: 5) &&
            (ignoreUntil == null || DateTime.now().isAfter(ignoreUntil));
        _position = resetAtEnd ? _duration : reportedPosition;
        if (value.TrackDurationInt > 0) {
          _duration = Duration(seconds: value.TrackDurationInt);
        }
        notifyListeners();
        _scheduleAutoNextPart();
      });
      renderer.device.positionPoller.start();
      _scheduleAutoNextPart();
      return true;
    } catch (error) {
      _error = '投屏失败，请确认电视支持 DLNA 在线视频：$error';
      return false;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  String _partTitle(String title, int part, int partCount) =>
      partCount > 1 ? '$title · P$part' : title;

  Future<void> selectPart(int part) async {
    final renderer = _connected;
    if (renderer == null || part == _currentPart || _switchingPart) return;
    final target = _parts.cast<DlnaCastPart?>().firstWhere(
      (item) => item?.part == part,
      orElse: () => null,
    );
    if (target == null) return;
    _switchingPart = true;
    _autoNextTimer?.cancel();
    _error = null;
    notifyListeners();
    try {
      await renderer.device.setUrl(
        target.url,
        title: _partTitle(_title, target.part, _parts.length),
        type: VideoMime.any,
      );
      await renderer.device.play();
      _currentPart = target.part;
      _position = Duration.zero;
      _duration = target.duration;
      _playing = true;
      // 部分设备会在换源后短暂上报上一个分 P 的结束进度。
      _ignoreCompletionUntil = DateTime.now().add(const Duration(seconds: 2));
    } catch (error) {
      _error = '切换到 P$part 失败：$error';
    } finally {
      _switchingPart = false;
      _scheduleAutoNextPart();
      notifyListeners();
    }
  }

  void _scheduleAutoNextPart() {
    _autoNextTimer?.cancel();
    if (_switchingPart || _parts.length < 2 || _duration <= Duration.zero) {
      return;
    }
    final currentIndex = _parts.indexWhere((item) => item.part == _currentPart);
    if (currentIndex < 0 || currentIndex + 1 >= _parts.length) return;
    final ignoreUntil = _ignoreCompletionUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) return;
    final remaining = _duration - _position;
    if (remaining > const Duration(seconds: 1)) {
      final scheduledPart = _currentPart;
      _autoNextTimer = Timer(remaining + const Duration(seconds: 1), () {
        if (_playing && _currentPart == scheduledPart) {
          _advanceToNextPart();
        }
      });
      return;
    }
    _advanceToNextPart();
  }

  void _advanceToNextPart() {
    final index = _parts.indexWhere((item) => item.part == _currentPart);
    if (index < 0 || index + 1 >= _parts.length) return;
    unawaited(selectPart(_parts[index + 1].part));
  }

  Future<void> play() async {
    final renderer = _connected;
    if (renderer == null) return;
    await renderer.device.play();
    _playing = true;
    _scheduleAutoNextPart();
    notifyListeners();
  }

  Future<void> pause() async {
    final renderer = _connected;
    if (renderer == null) return;
    await renderer.device.pause();
    _playing = false;
    _autoNextTimer?.cancel();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    final renderer = _connected;
    if (renderer == null) return;
    var target = position;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await renderer.device.seek(PositionParser.toStr(target.inSeconds));
    _position = target;
    _scheduleAutoNextPart();
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    final renderer = _connected;
    if (renderer == null) return;
    final next = (value.clamp(0.0, 1.0) * 100).round();
    await renderer.device.volume(next);
    _volume = next;
    notifyListeners();
  }

  /// 主动向电视刷新进度、播放状态和音量。
  ///
  /// 不同 DLNA 设备支持的查询能力不完全一致，因此逐项容错；任意一项
  /// 成功都会更新面板，避免某个不支持的接口拖累全部状态刷新。
  Future<void> refreshStatus() async {
    final renderer = _connected;
    if (renderer == null || _refreshing) return;
    _refreshing = true;
    _error = null;
    notifyListeners();
    var refreshed = false;
    final positionBeforeRefresh = _position;
    var stopped = false;
    try {
      try {
        final value = PositionParser(await renderer.device.position());
        _position = Duration(seconds: value.RelTimeInt);
        if (value.TrackDurationInt > 0) {
          _duration = Duration(seconds: value.TrackDurationInt);
        }
        refreshed = true;
      } catch (_) {}
      try {
        final value = TransportInfoParser(
          await renderer.device.getTransportInfo(),
        );
        final state = value.CurrentTransportState.toUpperCase();
        _playing = state == 'PLAYING';
        stopped = state == 'STOPPED' || state == 'NO_MEDIA_PRESENT';
        refreshed = true;
      } catch (_) {}
      try {
        _volume = VolumeParser(await renderer.device.getVolume()).current;
        refreshed = true;
      } catch (_) {}
      if (stopped &&
          _duration > Duration.zero &&
          positionBeforeRefresh >= _duration - const Duration(seconds: 5)) {
        _position = _duration;
      }
      if (!refreshed) _error = '刷新投屏状态失败，请检查电视连接';
      _scheduleAutoNextPart();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final renderer = _connected;
    _connected = null;
    _playing = false;
    _parts = const [];
    _currentPart = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _ignoreCompletionUntil = null;
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    renderer?.device.positionPoller.stop();
    if (renderer != null) {
      try {
        await renderer.device.stop();
      } catch (_) {}
    }
    notifyListeners();
  }
}
