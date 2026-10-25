/// Navigo v5.1 — design tokens.
///
/// v5.1 CONTRACT (user-mandated): the APP has exactly two looks — light and
/// dark. Everything the user used to see as "Graphite / Noir / Forest …" now
/// lives in the MAP STYLE dimension (see style_pack.dart): those are colors
/// of the cartography itself, premium hosted basemaps, not app skins.
///
/// Each app look still carries a full map-token set — used for the route
/// line, selection pulse and sprite tinting so overlays stay readable on
/// every basemap.
library;

import 'package:flutter/material.dart';

/// Map-paint tokens for one palette.
class LuxMapColors {
  const LuxMapColors({
    required this.background,
    required this.landcover,
    required this.park,
    required this.urban,
    required this.water,
    required this.waterway,
    required this.building,
    required this.buildingExtrusion,
    required this.boundary,
    required this.rail,
    required this.path,
    required this.serviceRoad,
    required this.minorRoad,
    required this.tertiary,
    required this.secondary,
    required this.primaryRoad,
    required this.trunk,
    required this.motorway,
    required this.roadCasing,
    required this.label,
    required this.labelHalo,
    required this.roadLabel,
    required this.route,
    required this.routeCasing,
    required this.traveled,
    required this.poi,
  });

  final String background, landcover, park, urban, water, waterway;
  final String building, buildingExtrusion, boundary, rail;
  final String path, serviceRoad, minorRoad, tertiary, secondary;
  final String primaryRoad, trunk, motorway, roadCasing;
  final String label, labelHalo, roadLabel, route, routeCasing, traveled, poi;
}

/// One app look: UI colors + overlay map colors + meta.
class LuxTheme {
  const LuxTheme({
    required this.id,
    required this.title,
    required this.isDark,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.outline,
    required this.onBackground,
    required this.textMuted,
    required this.map,
  });

  final String id, title;
  final bool isDark;
  final Color primary, onPrimary, secondary;
  final Color background, surface, surfaceAlt, outline, onBackground, textMuted;
  final LuxMapColors map;

  MaterialColor get materialPrimary {
    final c = primary;
    return MaterialColor(
      c.toARGB32(),
      <int, Color>{
        50: c.withValues(alpha: 0.06),
        100: c.withValues(alpha: 0.14),
        200: c.withValues(alpha: 0.24),
        300: c.withValues(alpha: 0.38),
        400: c.withValues(alpha: 0.62),
        500: c,
        600: Color.lerp(c, Colors.black, 0.12)!,
        700: Color.lerp(c, Colors.black, 0.26)!,
        800: Color.lerp(c, Colors.black, 0.42)!,
        900: Color.lerp(c, Colors.black, 0.58)!,
      },
    );
  }
}

LuxMapColors _m({
  required String background,
  required String landcover,
  required String park,
  required String urban,
  required String water,
  required String waterway,
  required String building,
  required String buildingExtrusion,
  required String boundary,
  required String rail,
  required String path,
  required String serviceRoad,
  required String minorRoad,
  required String tertiary,
  required String secondary,
  required String primaryRoad,
  required String trunk,
  required String motorway,
  required String roadCasing,
  required String label,
  required String labelHalo,
  required String roadLabel,
  required String route,
  required String routeCasing,
  required String traveled,
  required String poi,
}) =>
    LuxMapColors(
      background: background,
      landcover: landcover,
      park: park,
      urban: urban,
      water: water,
      waterway: waterway,
      building: building,
      buildingExtrusion: buildingExtrusion,
      boundary: boundary,
      rail: rail,
      path: path,
      serviceRoad: serviceRoad,
      minorRoad: minorRoad,
      tertiary: tertiary,
      secondary: secondary,
      primaryRoad: primaryRoad,
      trunk: trunk,
      motorway: motorway,
      roadCasing: roadCasing,
      label: label,
      labelHalo: labelHalo,
      roadLabel: roadLabel,
      route: route,
      routeCasing: routeCasing,
      traveled: traveled,
      poi: poi,
    );

const Color _cDayAccent = Color(0xFF1E7A6F);
const Color _cNightAccent = Color(0xFF4FD8C4);

/// v5.1: EXACTLY TWO app looks (user: «темы самого приложения две — светлая
/// и тёмная — и всё»).
final List<LuxTheme> kLuxThemes = [
  // ── Light ────────────────────────────────────────────────────────────────
  LuxTheme(
    id: 'day',
    title: 'Светлая',
    isDark: false,
    primary: _cDayAccent,
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFFB76B3A),
    background: Color(0xFFF6F5F0),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFEEE8),
    outline: Color(0xFFDBD9D0),
    onBackground: Color(0xFF23262A),
    textMuted: Color(0xFF6C7370),
    map: _m(
      background: 'f4f2ec',
      landcover: 'e3ead9',
      park: 'cfe6c8',
      urban: 'eceadf',
      water: 'a9d3e8',
      waterway: '8fc4de',
      building: 'e2dfd4',
      buildingExtrusion: 'd6d2c4',
      boundary: 'b3aa98',
      rail: 'c2bdb0',
      path: 'c9c2b2',
      serviceRoad: 'd9d4c6',
      minorRoad: 'ffffff',
      tertiary: 'fffdf5',
      secondary: 'fff4d9',
      primaryRoad: 'ffe7ae',
      trunk: 'ffd98f',
      motorway: 'f8cd7c',
      roadCasing: 'd8d2c2',
      label: '3d4440',
      labelHalo: 'ffffff',
      roadLabel: '6d7470',
      route: '2F7DF6',
      routeCasing: 'ffffff',
      traveled: 'b9c2cf',
      poi: '7b837e',
    ),
  ),
  // ── Dark ─────────────────────────────────────────────────────────────────
  LuxTheme(
    id: 'night',
    title: 'Тёмная',
    isDark: true,
    primary: _cNightAccent,
    onPrimary: Color(0xFF00261F),
    secondary: Color(0xFFFFB054),
    background: Color(0xFF101317),
    surface: Color(0xFF171B21),
    surfaceAlt: Color(0xFF1F252E),
    outline: Color(0xFF2A323D),
    onBackground: Color(0xFFECF0F5),
    textMuted: Color(0xFF9AA4B2),
    map: _m(
      background: '111418',
      landcover: '151b15',
      park: '1b3320',
      urban: '16191d',
      water: '17293a',
      waterway: '1d3448',
      building: '1f242c',
      buildingExtrusion: '2a313c',
      boundary: '3f4854',
      rail: '272d36',
      path: '3a424e',
      serviceRoad: '333b46',
      minorRoad: '3c4552',
      tertiary: '4a5462',
      secondary: '5a6575',
      primaryRoad: '6e7a8c',
      trunk: '7e8b9e',
      motorway: '8fa0b5',
      roadCasing: '0d1014',
      label: 'e9edf3',
      labelHalo: '111418',
      roadLabel: 'a8b3c2',
      route: 'FFB054',
      routeCasing: '0b0d10',
      traveled: '5a6575',
      poi: 'aeb8c6',
    ),
  ),
];

LuxTheme luxThemeById(String id) {
  for (final t in kLuxThemes) {
    if (t.id == id) return t;
  }
  // Migration ≤5.0: every legacy palette folds into the matching LIGHT or
  // DARK app look. The palettes themselves live on as MAP styles.
  const legacyDark = {'graphite', 'noir', 'midnight', 'forest', 'violet'};
  const legacyLight = {'pearl', 'sand', 'arctic', 'rose'};
  if (legacyDark.contains(id)) return luxThemeById('night');
  if (legacyLight.contains(id)) return luxThemeById('day');
  return kLuxThemes.first;
}
