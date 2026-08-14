import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _defaultSeed = Color(0xFF66CCFF);

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.primary, required this.accent});

  final Color primary;
  final Color accent;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      const AppPalette(primary: _defaultSeed, accent: Colors.pink);

  @override
  AppPalette copyWith({Color? primary, Color? accent}) => AppPalette(
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

AppPalette appPaletteFromSeed(Color seed) {
  final hue = HSLColor.fromColor(seed).hue;
  return AppPalette(
    primary: seed,
    accent: HSLColor.fromColor(seed)
        .withHue((hue + 110) % 360)
        .withSaturation(0.9)
        .withLightness(0.55)
        .toColor(),
  );
}

ThemeData buildAppTheme(Color seed) {
  final palette = appPaletteFromSeed(seed);
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xfffafaff),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: const CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.white,
      color: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Colors.blueGrey),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    extensions: [palette],
  );
}

class ThemeSettings {
  static const _key = 'app_theme_seed';

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
}
