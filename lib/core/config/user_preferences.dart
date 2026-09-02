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
  static const _keyBackgroundPlay = 'pref.background_play';
  static const _keyArticleScrollbar = 'pref.article_scrollbar';
  static const _keyShowDislike = 'pref.player_show_dislike';
  static const _keyLandscapeSideRatio = 'pref.landscape_side_ratio';
  static const _keyLatestMarkedIds = 'pref.latest_marked_ids';

  /// 横屏播放页右侧简介/评论栏宽度占整屏宽的比例，可选 1/2、1/3、1/4、1/5。
  static const landscapeSideRatios = [1 / 2, 1 / 3, 1 / 4, 1 / 5];

  /// 默认比例：右侧简介/评论栏占整屏 1/3。
  static const defaultLandscapeSideRatio = 1 / 3;

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

  /// 后台播放开关（Beta）：退到后台时视频继续播放声音，默认关闭。
  static Future<bool> loadBackgroundPlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyBackgroundPlay) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveBackgroundPlay(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBackgroundPlay, enabled);
    } catch (_) {}
  }

  /// 文章阅读进度滑块开关：长文章右侧显示可拖拽的阅读进度条，
  /// 默认关闭。
  static Future<bool> loadArticleScrollbar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyArticleScrollbar) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveArticleScrollbar(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyArticleScrollbar, enabled);
    } catch (_) {}
  }

  /// 竖屏播放页是否显示点踩按钮，默认关闭。
  static Future<bool> loadShowDislike() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyShowDislike) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveShowDislike(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowDislike, enabled);
    } catch (_) {}
  }

  /// 横屏播放页右侧简介/评论栏宽度占整屏宽的比例，默认 1/3。
  static Future<double> loadLandscapeSideRatio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyLandscapeSideRatio) ??
          defaultLandscapeSideRatio;
    } catch (_) {
      return defaultLandscapeSideRatio;
    }
  }

  static Future<void> saveLandscapeSideRatio(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLandscapeSideRatio, value);
    } catch (_) {}
  }

  /// 最新页已标记（折叠）的资源 stableId 集合，本地持久化，
  /// 重启后仍过滤这些内容，避免被标记的内容重新出现。
  static Future<Set<String>> loadLatestMarkedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_keyLatestMarkedIds) ?? const [])
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> saveLatestMarkedIds(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyLatestMarkedIds, ids.toList());
    } catch (_) {}
  }
}
