import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 播放链路统一日志。
///
/// - Android：通过原生 MethodChannel 写 `Log.d("MfunsPlayback", ...)`，
///   可直接用 `adb logcat -s MfunsPlayback:D` 过滤。
/// - 其他平台：退化为 `debugPrint`，前缀保持 `MfunsPlayback:` 便于 grep。
///
/// 只记录播放关键事件，不刷普通业务日志。
class PlaybackLog {
  PlaybackLog._();

  static const MethodChannel _channel =
      MethodChannel('com.ygen.mfuns_flutter/playback_log');

  static void d(String message) {
    final line = 'MfunsPlayback: $message';
    if (!kIsWeb && Platform.isAndroid) {
      // 原生侧没有注册通道（例如 iOS/桌面）时静默失败。
      _channel
          .invokeMethod<void>('log', message)
          .catchError((Object _) {});
    } else {
      debugPrint(line);
    }
  }
}
