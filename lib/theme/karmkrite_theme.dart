import 'package:flutter/material.dart';

/// KARMKRITE's shared visual language.
/// Royal Maroon, Antique Gold and Sandalwood are the canonical brand colors.
abstract final class KarmKritePalette {
  static const maroon = Color(0xFF681D24);
  static const maroonDeep = Color(0xFF421219);
  static const maroonSoft = Color(0xFF8A343C);
  static const gold = Color(0xFFC69A43);
  static const goldLight = Color(0xFFE5C77E);
  static const sandalwood = Color(0xFFF4EBDD);
  static const paper = Color(0xFFFFFBF5);
  static const beige = Color(0xFFE4D2B5);
  static const copper = Color(0xFFA64B32);
  static const wood = Color(0xFF392B28);
  static const ink = Color(0xFF302522);
  static const muted = Color(0xFF756963);
  static const border = Color(0xFFE5D8C5);
  static const darkBackground = Color(0xFF171214);
  static const darkSurface = Color(0xFF241B1D);
  static const darkElevated = Color(0xFF302326);
  static const darkText = Color(0xFFF5EDE4);
  static const darkMuted = Color(0xFFC4B5AE);
}

abstract final class KarmKriteTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: KarmKritePalette.maroon,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFF1DDE0),
      onPrimaryContainer: Color(0xFF421219),
      secondary: KarmKritePalette.gold,
      onSecondary: Color(0xFF241600),
      secondaryContainer: Color(0xFFF4E4BF),
      onSecondaryContainer: Color(0xFF49330A),
      tertiary: KarmKritePalette.copper,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFF5DED4),
      onTertiaryContainer: Color(0xFF512012),
      error: Color(0xFFBA1A1A),
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: KarmKritePalette.paper,
      onSurface: KarmKritePalette.ink,
      surfaceContainerHighest: KarmKritePalette.sandalwood,
      onSurfaceVariant: KarmKritePalette.muted,
      outline: Color(0xFF8C8177),
      outlineVariant: KarmKritePalette.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: KarmKritePalette.wood,
      onInverseSurface: Colors.white,
      inversePrimary: KarmKritePalette.goldLight,
      surfaceTint: KarmKritePalette.maroon,
    );
    return _build(scheme, dark: false);
  }

  static ThemeData get dark {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: KarmKritePalette.goldLight,
      onPrimary: KarmKritePalette.maroonDeep,
      primaryContainer: Color(0xFF5B242B),
      onPrimaryContainer: Color(0xFFFFE1E4),
      secondary: KarmKritePalette.gold,
      onSecondary: Color(0xFF2D1D00),
      secondaryContainer: Color(0xFF59451F),
      onSecondaryContainer: Color(0xFFFFE3A8),
      tertiary: Color(0xFFE69A7C),
      onTertiary: Color(0xFF4A1607),
      tertiaryContainer: Color(0xFF653322),
      onTertiaryContainer: Color(0xFFFFDBCC),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: KarmKritePalette.darkBackground,
      onSurface: KarmKritePalette.darkText,
      surfaceContainerHighest: KarmKritePalette.darkElevated,
      onSurfaceVariant: KarmKritePalette.darkMuted,
      outline: Color(0xFF9B8982),
      outlineVariant: Color(0xFF514044),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: KarmKritePalette.sandalwood,
      onInverseSurface: KarmKritePalette.ink,
      inversePrimary: KarmKritePalette.maroon,
      surfaceTint: KarmKritePalette.gold,
    );
    return _build(scheme, dark: true);
  }

  static ThemeData _build(ColorScheme scheme, {required bool dark}) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.brightness == Brightness.light
          ? KarmKritePalette.sandalwood
          : KarmKritePalette.darkBackground,
      canvasColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? KarmKritePalette.maroonDeep : KarmKritePalette.maroon,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800,
          letterSpacing: .35,
        ),
        iconTheme: const IconThemeData(color: KarmKritePalette.goldLight),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? KarmKritePalette.darkSurface : KarmKritePalette.maroonDeep,
        indicatorColor: dark ? const Color(0xFF633039) : const Color(0xFF81343D),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? KarmKritePalette.goldLight
              : (dark ? KarmKritePalette.darkMuted : const Color(0xFFE8D9D3)),
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? KarmKritePalette.goldLight
              : (dark ? KarmKritePalette.darkMuted : const Color(0xFFE8D9D3)),
        )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? KarmKritePalette.darkElevated : Colors.white,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: scheme.secondary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: dark ? KarmKritePalette.gold : KarmKritePalette.maroon,
          foregroundColor: dark ? KarmKritePalette.maroonDeep : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.secondary),
      chipTheme: baseChipTheme(scheme),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? KarmKritePalette.darkElevated : KarmKritePalette.wood,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
    );
  }

  static ChipThemeData baseChipTheme(ColorScheme scheme) => ChipThemeData(
    backgroundColor: scheme.surfaceContainerHighest,
    selectedColor: scheme.primaryContainer,
    side: BorderSide(color: scheme.outlineVariant),
    labelStyle: TextStyle(color: scheme.onSurface),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );
}
