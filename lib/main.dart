import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/mfuns_app.dart';

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
  runApp(MfunsApp(controller: AppController()));
}
