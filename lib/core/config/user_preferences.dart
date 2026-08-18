import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// 用户偏好设置（默认清晰度、弹幕开关/透明度/字号），本地持久化。
class UserPreferences {
  static const _keyDefaultQuality = 'pref.default_quality';
  static const _keyDanmakuOn = 'pref.danmaku_on';
  static const _keyDanmakuOpacity = 'pref.danmaku_opacity';
  static const _keyDanmakuSize = 'pref.danmaku_size';
  static const _keyAutoPlay = 'pref.autoplay';
  static const _keyAutoSignIn = 'pref.auto_sign_in';
  static const _keyAcceleratorBase = 'pref.accelerator_base';

  /// 自定义 GitHub 加速地址（用于更新清单与下载），默认官方加速站。
  static Future<String> loadAcceleratorBase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyAcceleratorBase)?.trim() ?? '';
      return value.isEmpty ? AppConfig.defaultAcceleratorBase : value;
    } catch (_) {
      return AppConfig.defaultAcceleratorBase;
    }
  }

  static Future<void> saveAcceleratorBase(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAcceleratorBase, value.trim());
    } catch (_) {}
  }

  /// 自动签到开关：开启后应用在打开状态下每天零点尝试签到。
  static Future<bool> loadAutoSignIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoSignIn) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveAutoSignIn(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoSignIn, enabled);
    } catch (_) {}
  }

  /// 默认清晰度标签（如 `720p`）；空字符串表示自动（列表第一个可用清晰度）。
  static Future<String> loadDefaultQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyDefaultQuality) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveDefaultQuality(String label) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultQuality, label);
    } catch (_) {}
  }

  static Future<bool> loadDanmakuOn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyDanmakuOn) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveDanmakuOn(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDanmakuOn, enabled);
    } catch (_) {}
  }

  static Future<double> loadDanmakuOpacity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyDanmakuOpacity) ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  static Future<void> saveDanmakuOpacity(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDanmakuOpacity, value);
    } catch (_) {}
  }

  static Future<double> loadDanmakuSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyDanmakuSize) ?? 20.0;
    } catch (_) {
      return 20.0;
    }
  }

  static Future<void> saveDanmakuSize(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDanmakuSize, value);
    } catch (_) {}
  }

  /// 打开视频后是否自动播放，默认开启。
  static Future<bool> loadAutoPlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoPlay) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveAutoPlay(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoPlay, enabled);
    } catch (_) {}
  }
}
