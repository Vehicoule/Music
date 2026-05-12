import 'package:flutter/material.dart';

class StreamboxTheme {
  const StreamboxTheme._();

  static const background = Color(0xfff7f2eb);
  static const surface = Color(0xdffffaf4);
  static const surfaceStrong = Color(0xfffbf8f1);
  static const outline = Color(0x66b8aea4);
  static const text = Color(0xff222827);
  static const muted = Color(0xff6d7774);
  static const mint = Color(0xff8edcc8);
  static const sage = Color(0xffdceade);
  static const peach = Color(0xffffdfcf);
  static const lavender = Color(0xffddd7ff);
  static const warning = Color(0xffa94f48);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: mint,
      brightness: Brightness.light,
      surface: surfaceStrong,
      primary: const Color(0xff337f6c),
      secondary: const Color(0xff8d6f55),
      error: warning,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      dividerColor: outline,
      textTheme: Typography.material2021().black.apply(
            bodyColor: text,
            displayColor: text,
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mint,
          foregroundColor: const Color(0xff15362f),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          disabledForegroundColor: muted.withValues(alpha: 0.45),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.58),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xff68b8a3), width: 1.4),
        ),
        hintStyle: const TextStyle(color: muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.48),
        selectedColor: sage,
        side: const BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        labelStyle: const TextStyle(
          color: text,
          fontWeight: FontWeight.w600,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Color(0xff75c9b2),
        inactiveTrackColor: Color(0x669aa7a3),
        thumbColor: Color(0xff5eb59e),
      ),
    );
  }
}
