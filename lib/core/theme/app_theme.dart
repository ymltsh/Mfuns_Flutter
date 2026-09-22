import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _defaultSeed = Color(0xFF5094B2);

/// Edge-to-edge 系统栏样式。导航栏保持透明，让页面背景延伸到 Android
/// 手势导航条（“小白条”）后方；图标颜色随主题切换以维持可读性。
SystemUiOverlayStyle appSystemUiOverlayStyle({
  required Brightness brightness,
  Brightness statusBarIconBrightness = Brightness.light,
}) {
  final navigationIconBrightness = brightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: statusBarIconBrightness,
    statusBarBrightness: statusBarIconBrightness == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: navigationIconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 主题模式：跟随系统 / 强制浅色 / 强制深色。
enum AppThemeMode { system, light, dark }

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primary,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.chip,
    required this.placeholder,
    required this.divider,
  });

  final Color primary;
  final Color accent;

  /// 卡片 / 面板 / 弹层背景。
  final Color surface;

  /// 主要文字。
  final Color ink;

  /// 次要文字 / 弱图标。
  final Color muted;

  /// 标签、输入框等浅色填充背景。
  final Color chip;

  /// 图片加载失败 / 空内容占位背景。
  final Color placeholder;

  /// 分割线 / 拖拽手柄。
  final Color divider;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? lightPalette;

  /// 浅色模式的默认配色（未挂载主题时的兜底）。
  static const AppPalette lightPalette = AppPalette(
    primary: _defaultSeed,
    accent: Colors.pink,
    surface: Colors.white,
    ink: Colors.blueGrey,
    muted: Colors.blueGrey,
    chip: Color(0xfff4f3f8),
    placeholder: Color(0xffefeff7),
    divider: Color(0xffdedde7),
  );

  @override
  AppPalette copyWith({
    Color? primary,
    Color? accent,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? chip,
    Color? placeholder,
    Color? divider,
  }) => AppPalette(
    primary: primary ?? this.primary,
    accent: accent ?? this.accent,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    chip: chip ?? this.chip,
    placeholder: placeholder ?? this.placeholder,
    divider: divider ?? this.divider,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

AppPalette appPaletteFromSeed(
  Color seed, {
  Brightness brightness = Brightness.light,
}) {
  final dark = brightness == Brightness.dark;
  final hue = HSLColor.fromColor(seed).hue;
  return AppPalette(
    primary: seed,
    accent: HSLColor.fromColor(seed)
        .withHue((hue + 110) % 360)
        .withSaturation(0.9)
        .withLightness(dark ? 0.62 : 0.55)
        .toColor(),
    surface: dark ? const Color(0xFF1C1F26) : Colors.white,
    ink: dark ? const Color(0xFFE7EBF0) : Colors.blueGrey,
    muted: dark ? const Color(0xFF9AA4AF) : Colors.blueGrey,
    chip: dark ? const Color(0xFF262A33) : const Color(0xfff4f3f8),
    placeholder: dark ? const Color(0xFF22252D) : const Color(0xffefeff7),
    divider: dark ? const Color(0xFF2E323B) : const Color(0xffdedde7),
  );
}

ThemeData buildAppTheme(
  Color seed, {
  Brightness brightness = Brightness.light,
}) {
  final dark = brightness == Brightness.dark;
  final palette = appPaletteFromSeed(seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    scaffoldBackgroundColor: dark
        ? const Color(0xFF121419)
        : const Color(0xfffafaff),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: appSystemUiOverlayStyle(
        brightness: brightness,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      color: palette.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: .5,
      space: 1,
    ),
    extensions: [palette],
  );
}

class ThemeSettings {
  static const _key = 'app_theme_seed';
  static const _modeKey = 'app_theme_mode';
  static const _backgroundImageKey = 'app_background_image';
  static const _backgroundOpacityKey = 'app_background_opacity';

  /// 自定义背景图的默认透明度，兼顾图片辨识度与前景内容可读性。
  static const defaultBackgroundOpacity = 0.35;

  static Future<Color> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_key);
      if (value == null) return _defaultSeed;
      return Color(value);
    } catch (_) {
      return _defaultSeed;
    }
  }

  static Future<void> save(Color color) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, color.value);
    } catch (_) {
      // 保存失败时忽略，仅本次会话生效
    }
  }

  static Future<AppThemeMode> loadMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_modeKey);
      if (index == null) return AppThemeMode.system;
      return AppThemeMode.values[index % AppThemeMode.values.length];
    } catch (_) {
      return AppThemeMode.system;
    }
  }

  static Future<void> saveMode(AppThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_modeKey, mode.index);
    } catch (_) {
      // 保存失败时忽略，仅本次会话生效
    }
  }

  static Future<String> loadBackgroundImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_backgroundImageKey)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveBackgroundImage(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (path.trim().isEmpty) {
        await prefs.remove(_backgroundImageKey);
      } else {
        await prefs.setString(_backgroundImageKey, path.trim());
      }
    } catch (_) {
      // 保存失败时忽略，仅本次会话生效
    }
  }

  static Future<double> loadBackgroundOpacity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getDouble(_backgroundOpacityKey) ??
              defaultBackgroundOpacity)
          .clamp(0.0, 1.0);
    } catch (_) {
      return defaultBackgroundOpacity;
    }
  }

  static Future<void> saveBackgroundOpacity(double opacity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_backgroundOpacityKey, opacity.clamp(0.0, 1.0));
    } catch (_) {
      // 保存失败时忽略，仅本次会话生效
    }
  }
}
