import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/mfuns_app.dart';
import 'core/media/media_notification.dart';
import 'core/network/link_router.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端初始化窗口管理插件（全屏切换等能力）。
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    try {
      await windowManager.ensureInitialized();
    } catch (_) {
      // 插件初始化失败不影响常规使用。
    }
  }
  // 全局沉浸式布局：状态栏透明，内容可延伸到系统栏区域，
  // 由各页面自行处理 inset（如 masthead/AppBar 的背景延伸）。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // 媒体播放通知（Android MediaSession / iOS 控制中心）单例 Handler。
  try {
    await AudioService.init(
      builder: () => MfunsAudioHandler.instance,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.ygen.mfuns_flutter.media',
        androidNotificationChannelName: '媒体播放',
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (_) {
    // 平台不支持时静默，视频播放不受影响。
  }
  final controller = AppController();
  runApp(MfunsApp(controller: controller, navigatorKey: _navigatorKey));
  // 链接唤醒：mfuns:// 协议与 mfuns.net / mfuns.wgen.top 深链打开对应页面。
  LinkRouter(controller: controller, navigatorKey: _navigatorKey).start();
}
