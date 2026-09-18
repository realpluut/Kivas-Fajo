import 'package:flutter/material.dart';

/// Selectable visual styles for dark mode. Light mode has no styles -- it's
/// always the plain Material theme below.
enum AppThemeStyle { borg, federation, klingon, romulan }

extension AppThemeStyleLabels on AppThemeStyle {
  String get label => switch (this) {
        AppThemeStyle.borg => 'Borg',
        AppThemeStyle.federation => 'Federation',
        AppThemeStyle.klingon => 'Klingon',
        AppThemeStyle.romulan => 'Romulan',
      };

  String get description => switch (this) {
        AppThemeStyle.borg => 'Black void with a phosphor-green glow',
        AppThemeStyle.federation => 'LCARS/Okudagram-style panels in orange, violet and salmon',
        AppThemeStyle.klingon => 'Blood-red and bronze on near-black, sharp angular accents',
        AppThemeStyle.romulan => 'Teal-emerald and gunmetal, swept warbird curves and a cloaked shimmer',
      };
}

/// Light theme: plain Material, unchanged.
ThemeData buildLightTheme() {
  return ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo));
}

/// Dark theme, in one of three visual styles. All three share the same
/// structural trick: a transparent scaffold background so the matching
/// painted background (see widgets/themed_background.dart) shows through,
/// with solid app bar/nav bar chrome on top so navigation stays crisp.
ThemeData buildDarkTheme(AppThemeStyle style) {
  return switch (style) {
    AppThemeStyle.borg => _buildBorgTheme(),
    AppThemeStyle.federation => _buildFederationTheme(),
    AppThemeStyle.klingon => _buildKlingonTheme(),
    AppThemeStyle.romulan => _buildRomulanTheme(),
  };
}

ThemeData _buildBorgTheme() {
  const borgGreen = Color(0xFF39FF14);
  const borgAmber = Color(0xFFFFC400);
  const voidBlack = Color(0xFF060907);
  const panelSurface = Color(0xFF0E1610);
  const panelSurfaceHigh = Color(0xFF16211A);
  const gridLine = Color(0xFF1F3D26);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: borgGreen,
    brightness: Brightness.dark,
  ).copyWith(
    primary: borgGreen,
    onPrimary: Colors.black,
    secondary: borgAmber,
    onSecondary: Colors.black,
    surface: panelSurface,
    onSurface: const Color(0xFFE3F5E8),
    surfaceContainerHighest: panelSurfaceHigh,
    outline: gridLine,
    error: const Color(0xFFFF5252),
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(backgroundColor: voidBlack, foregroundColor: borgGreen),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: voidBlack,
      indicatorColor: borgGreen.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? borgGreen : Colors.grey),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(color: states.contains(WidgetState.selected) ? borgGreen : Colors.grey, fontSize: 12),
      ),
    ),
    cardTheme: const CardThemeData(color: panelSurface),
    dividerTheme: const DividerThemeData(color: gridLine),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: borgGreen),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? borgGreen : null),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? borgGreen : null),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: borgGreen, foregroundColor: Colors.black),
  );
}

/// Federation theme: LCARS/Okudagram-inspired -- black backdrop, warm LCARS
/// orange as the primary accent, a cool blue-violet secondary, and salmon as
/// a tertiary highlight, echoing the classic Okuda console palette.
ThemeData _buildFederationTheme() {
  const lcarsOrange = Color(0xFFFF9C41);
  const lcarsViolet = Color(0xFF9999FF);
  const lcarsSalmon = Color(0xFFFF8577);
  const voidBlack = Color(0xFF000000);
  const panelSurface = Color(0xFF0D0D14);
  const panelSurfaceHigh = Color(0xFF16161F);
  const gridLine = Color(0xFF3A3A4A);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: lcarsOrange,
    brightness: Brightness.dark,
  ).copyWith(
    primary: lcarsOrange,
    onPrimary: Colors.black,
    secondary: lcarsViolet,
    onSecondary: Colors.black,
    tertiary: lcarsSalmon,
    onTertiary: Colors.black,
    surface: panelSurface,
    onSurface: const Color(0xFFF2EFE9),
    surfaceContainerHighest: panelSurfaceHigh,
    outline: gridLine,
    error: const Color(0xFFFF5C5C),
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: voidBlack,
      foregroundColor: lcarsOrange,
      titleTextStyle: TextStyle(color: lcarsOrange, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: voidBlack,
      indicatorColor: lcarsOrange.withValues(alpha: 0.24),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? lcarsOrange : Colors.grey),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(color: states.contains(WidgetState.selected) ? lcarsOrange : Colors.grey, fontSize: 12),
      ),
    ),
    cardTheme: CardThemeData(color: panelSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    dividerTheme: const DividerThemeData(color: gridLine),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: lcarsOrange),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? lcarsOrange : null),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? lcarsOrange : null),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: lcarsOrange, foregroundColor: Colors.black),
  );
}

/// Klingon theme: near-black with a red undertone, blood-red primary, bronze
/// secondary -- sharp and martial rather than the Federation's rounded curves.
ThemeData _buildKlingonTheme() {
  const bloodRed = Color(0xFFC41E1E);
  const bronze = Color(0xFFB08D57);
  const voidBlack = Color(0xFF0A0505);
  const panelSurface = Color(0xFF160B0B);
  const panelSurfaceHigh = Color(0xFF201010);
  const gridLine = Color(0xFF3D1F1F);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: bloodRed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: bloodRed,
    onPrimary: Colors.white,
    secondary: bronze,
    onSecondary: Colors.black,
    surface: panelSurface,
    onSurface: const Color(0xFFF0E4E0),
    surfaceContainerHighest: panelSurfaceHigh,
    outline: gridLine,
    error: const Color(0xFFFF3B3B),
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: voidBlack,
      foregroundColor: bloodRed,
      titleTextStyle: TextStyle(color: bloodRed, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: voidBlack,
      indicatorColor: bloodRed.withValues(alpha: 0.24),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? bloodRed : Colors.grey),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(color: states.contains(WidgetState.selected) ? bloodRed : Colors.grey, fontSize: 12),
      ),
    ),
    cardTheme: CardThemeData(
      color: panelSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2), side: const BorderSide(color: gridLine)),
    ),
    dividerTheme: const DividerThemeData(color: gridLine),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: bloodRed),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? bloodRed : null),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? bloodRed : null),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: bloodRed, foregroundColor: Colors.white),
  );
}

/// Romulan theme: teal-emerald primary (the Star Empire's signature green,
/// tuned brighter than Vulcan/Borg green to read distinctly), gunmetal grey
/// secondary for the warbird-hull feel -- elegant and cold rather than the
/// Klingon's martial red or the Federation's warm orange.
ThemeData _buildRomulanTheme() {
  const romulanGreen = Color(0xFF00E5A0);
  const gunmetal = Color(0xFF8FA3AD);
  const voidBlack = Color(0xFF05100C);
  const panelSurface = Color(0xFF0B1D17);
  const panelSurfaceHigh = Color(0xFF13291F);
  const gridLine = Color(0xFF1E4A3A);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: romulanGreen,
    brightness: Brightness.dark,
  ).copyWith(
    primary: romulanGreen,
    onPrimary: Colors.black,
    secondary: gunmetal,
    onSecondary: Colors.black,
    surface: panelSurface,
    onSurface: const Color(0xFFE0F2EB),
    surfaceContainerHighest: panelSurfaceHigh,
    outline: gridLine,
    error: const Color(0xFFFF5C5C),
  );

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: voidBlack,
      foregroundColor: romulanGreen,
      titleTextStyle: TextStyle(color: romulanGreen, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.0),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: voidBlack,
      indicatorColor: romulanGreen.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? romulanGreen : Colors.grey),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(color: states.contains(WidgetState.selected) ? romulanGreen : Colors.grey, fontSize: 12),
      ),
    ),
    cardTheme: CardThemeData(
      color: panelSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: gridLine)),
    ),
    dividerTheme: const DividerThemeData(color: gridLine),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: romulanGreen),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? romulanGreen : null),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? romulanGreen : null),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: romulanGreen, foregroundColor: Colors.black),
  );
}
