import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/mfuns_app.dart';
import 'core/download/download_manager.dart';
import 'core/media/media_notification.dart';
import 'core/network/link_router.dart';
import 'core/notify/local_message_notifier.dart';

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
  // 后台音频引擎（just_audio）使用音乐播放的音频会话配置：
  // usage=media / contentType=music，配合 Android 前台媒体服务。
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {
    // 平台不支持时静默。
  }
  final controller = AppController();
  // 消息前台通知（Notification API）：初始化通道、请求权限；
  // 点击通知时回到根页面并跳转对应页面（私信/赞/评论/提及）。
  await LocalMessageNotifier.instance.init(onTap: (payload) {
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    switch (payload) {
      case LocalMessageNotifier.payloadLike:
        controller.openMessagesTab(subTab: 1, notifyTab: 0);
      case LocalMessageNotifier.payloadComment:
        controller.openMessagesTab(subTab: 1, notifyTab: 1);
      case LocalMessageNotifier.payloadMention:
        controller.openMessagesTab(subTab: 1, notifyTab: 2);
      case LocalMessageNotifier.payloadSystem:
        controller.openMessagesTab(subTab: 1, notifyTab: 3);
      default:
        controller.openMessagesTab();
    }
  });
  await LocalMessageNotifier.instance.requestPermission();
  runApp(MfunsApp(controller: controller, navigatorKey: _navigatorKey));
  // 链接唤醒：mfuns:// 协议与 mfuns.net / mfuns.wgen.top 深链打开对应页面。
  LinkRouter(controller: controller, navigatorKey: _navigatorKey).start();
  // 下载管理器：恢复数据库任务、检查临时文件并继续未完成下载。
  unawaited(DownloadManager.instance.initialize());
}
