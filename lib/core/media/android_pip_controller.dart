import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android 系统画中画桥接。
///
/// 原生 Activity 进入 PiP 后，应用根布局会只保留当前视频画面，避免把整页
/// 导航和评论区缩进系统小窗。
class AndroidPipController extends ChangeNotifier {
  AndroidPipController._() {
    if (_isAndroid) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  static final AndroidPipController instance = AndroidPipController._();
  static const _channel = MethodChannel('mfuns/picture_in_picture');

  bool _active = false;
  bool _entering = false;

  bool get isActive => _active;
  bool get isEntering => _entering;
  bool get shouldShowVideoSurface => _active || _entering;
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<bool> get isAvailable async {
    if (!_isAndroid) return false;
    return await _channel.invokeMethod<bool>('isAvailable') ?? false;
  }

  Future<bool> enter({int width = 16, int height = 9}) async {
    if (!_isAndroid || _entering) return false;
    _entering = true;
    notifyListeners();
    try {
      // 先让根布局完成纯视频帧，再请求 Android 缩入画中画。否则系统会把
      // 详情页或主页的上一帧作为 PiP 首帧，并可能一直保留该错误画面。
      await WidgetsBinding.instance.endOfFrame;
      final entered =
          await _channel.invokeMethod<bool>('enter', {
            'width': width,
            'height': height,
          }) ??
          false;
      if (!entered) {
        _entering = false;
        notifyListeners();
      }
      return entered;
    } on PlatformException {
      _entering = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onPipChanged') return;
    _active = call.arguments == true;
    _entering = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetActive(bool value) {
    _active = value;
    _entering = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetEntering(bool value) {
    _entering = value;
    notifyListeners();
  }
}
