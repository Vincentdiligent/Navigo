/// Map style catalog (v5.2): one source of truth for every MAP THEME the
/// app offers — the base packs (Classic / Graphite / Noir / Forest /
/// Satellite / Relief) and the ten premium recolors of Classic — used by
/// BOTH the layers sheet and the settings grid.
///
/// Each entry carries the localization keys, its group (base / light /
/// dark), a mini-palette for the preview painters and an accent color for
/// the selection ring. Light entries additionally know whether the theme is
/// dark (white card titles).
library;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import 'style_pack.dart';

Color _col(Clr c) => Color(0xFF000000 | (c.r << 16) | (c.g << 8) | c.b);

/// Everything the UI needs to render one map theme card.
class MapStyleInfo {
  const MapStyleInfo({
    required this.style,
    required this.titleKey,
    required this.subKey,
    required this.group,
    required this.dark,
    required this.accent,
    required this.land,
    required this.park,
    required this.water,
    required this.building,
    required this.casing,
    required this.minor,
    required this.major,
  });

  final MapStyle style;
  final String titleKey, subKey;

  /// 0 = base packs, 1 = light themes, 2 = dark themes.
  final int group;
  final bool dark;
  final Color accent;

  // Mini-map preview palette (the REAL theme values).
  final Color land, park, water, building, casing, minor, major;

  String title() => S.of(titleKey);
  String subtitle() => S.of(subKey);
}

final List<MapStyleInfo> kBaseStyles = [
  MapStyleInfo(
    style: MapStyle.classic,
    titleKey: 'styleClassic',
    subKey: 'styleClassicSub',
    group: 0,
    dark: false,
    accent: const Color(0xFF2F7DF6),
    land: const Color(0xFFF4F2EC),
    park: const Color(0xFFCFE6C8),
    water: const Color(0xFFA9D3E8),
    building: const Color(0xFFE2DFD4),
    casing: const Color(0xFFD8D2C2),
    minor: const Color(0xFFFFFFFF),
    major: const Color(0xFFF8CD7C),
  ),
  MapStyleInfo(
    style: MapStyle.graphite,
    titleKey: 'styleGraphite',
    subKey: 'styleGraphiteSub',
    group: 1,
    dark: false,
    accent: const Color(0xFF8A93A0),
    land: const Color(0xFFFAFAF8),
    park: const Color(0xFFE4E7E4),
    water: const Color(0xFFCAD6DE),
    building: const Color(0xFFE8E8E6),
    casing: const Color(0xFFC9C9C4),
    minor: const Color(0xFFFFFFFF),
    major: const Color(0xFFB9BDC2),
  ),
  MapStyleInfo(
    style: MapStyle.noir,
    titleKey: 'styleNoir',
    subKey: 'styleNoirSub',
    group: 2,
    dark: true,
    accent: const Color(0xFFFFD166),
    land: const Color(0xFF0E141B),
    park: const Color(0xFF12261A),
    water: const Color(0xFF0F2233),
    building: const Color(0xFF17171B),
    casing: const Color(0xFF080809),
    minor: const Color(0xFF33333D),
    major: const Color(0xFF8D8DA3),
  ),
  MapStyleInfo(
    style: MapStyle.forest,
    titleKey: 'styleForest',
    subKey: 'styleForestSub',
    group: 1,
    dark: false,
    accent: const Color(0xFF4E9E5F),
    land: const Color(0xFFE9EFE2),
    park: const Color(0xFFB7D4A4),
    water: const Color(0xFFA9D3E8),
    building: const Color(0xFFE3DED2),
    casing: const Color(0xFFC9CDB4),
    minor: const Color(0xFFFDFDF6),
    major: const Color(0xFFF3CE7B),
  ),
  MapStyleInfo(
    style: MapStyle.satellite,
    titleKey: 'satellite',
    subKey: 'satelliteSub',
    group: 0,
    dark: true,
    accent: const Color(0xFFE2B54B),
    land: const Color(0xFF243520),
    park: const Color(0xFF2E4426),
    water: const Color(0xFF1B3A4A),
    building: const Color(0xFF6B6B60),
    casing: const Color(0xFF3A4C2E),
    minor: const Color(0xFFD9D2BE),
    major: const Color(0xFFE8E4D8),
  ),
  MapStyleInfo(
    style: MapStyle.relief,
    titleKey: 'relief',
    subKey: 'reliefSub',
    group: 0,
    dark: false,
    accent: const Color(0xFFC25E12),
    land: const Color(0xFFEFF0E9),
    park: const Color(0xFFD5E6C4),
    water: const Color(0xFFA9D3E8),
    building: const Color(0xFFE0D8C0),
    casing: const Color(0xFFCFC5A8),
    minor: const Color(0xFFFFE7AE),
    major: const Color(0xFFE8B060),
  ),
  // v6.3 style bake-off: OSM Bright — the juicy OpenStreetMap classic.
  // Palette sampled from the live style (warm cream land, #aad3df water,
  // orange motorways). Same id family as Liberty → shared hit-test set.
  MapStyleInfo(
    style: MapStyle.bright,
    titleKey: 'styleBright',
    subKey: 'styleBrightSub',
    group: 1,
    dark: false,
    accent: const Color(0xFFE2734A),
    land: const Color(0xFFF8F4F0),
    park: const Color(0xFFCDE3B8),
    water: const Color(0xFFAAD3DF),
    building: const Color(0xFFDFD9D0),
    casing: const Color(0xFFD6CCC0),
    minor: const Color(0xFFFFFFFF),
    major: const Color(0xFFF0956F),
  ),
  // v6.5 mega-premium cartographies — the user's «совершенно другие
  // отрисовки»: Atlas & Onyx, complete Apple-Maps-like documents (own
  // road hierarchy, own POI chips, own label ladder). Palettes mirror the
  // REAL style-engine values (see apple_docs.dart).
  MapStyleInfo(
    style: MapStyle.silk,
    titleKey: 'styleSilk',
    subKey: 'styleSilkSub',
    group: 1,
    dark: false,
    accent: const Color(0xFF4C84E0),
    land: const Color(0xFFF2F2F7),
    park: const Color(0xFFD4EACE),
    water: const Color(0xFFA8D4F0),
    building: const Color(0xFFE0E0E4),
    casing: const Color(0xFFC8C8CC),
    minor: const Color(0xFFFFFFFF),
    major: const Color(0xFFE8A830),
  ),
  MapStyleInfo(
    style: MapStyle.onyx,
    titleKey: 'styleOnyx',
    subKey: 'styleOnyxSub',
    group: 2,
    dark: true,
    accent: const Color(0xFF65A1FD),
    land: const Color(0xFF1C1C1E),
    park: const Color(0xFF1D271D),
    water: const Color(0xFF0D2535),
    building: const Color(0xFF2C2C2E),
    casing: const Color(0xFF141416),
    minor: const Color(0xFF2C2C2E),
    major: const Color(0xFF544530),
  ),
];

/// The ten v5.2 premium recolors, driven by the SAME palettes the style
/// engine paints the real maps with — previews always match the world.
final List<MapStyleInfo> kPremiumInfos = [
  for (final s in kPremiumStyles)
    () {
      final p = kPremiumPalettes[s]!;
      return MapStyleInfo(
        style: s,
        titleKey: 'style${s.name[0].toUpperCase()}${s.name.substring(1)}',
        subKey: 'style${s.name[0].toUpperCase()}${s.name.substring(1)}Sub',
        group: p.dark ? 2 : 1,
        dark: p.dark,
        accent: _col(p.highway),
        land: _col(p.land),
        park: _col(p.park),
        water: _col(p.water),
        building: _col(p.building),
        casing: _col(p.roadCasing),
        minor: _col(p.road),
        major: _col(p.major),
      );
    }(),
];

/// All map themes in UI order: base packs → light themes → dark themes.
/// v6.6.1: relief left the catalog by user request; satellite stays as is.
/// The [MapStyle] enum keeps its slots — saved indices must not shift.
final List<MapStyleInfo> kMapStyleCatalog = [
  // Base
  kBaseStyles[0], // classic
  kBaseStyles[4], // satellite
  // Light
  kBaseStyles[1], // graphite
  kBaseStyles[6], // bright (v6.3 style bake-off)
  kBaseStyles[7], // silk (v6.5 mega-premium, Apple-like light)
  ...kPremiumInfos.where((i) => i.group == 1), // pearl/sand/arctic/rose/mint
  kBaseStyles[3], // forest
  // Dark
  kBaseStyles[2], // noir
  kBaseStyles[8], // onyx (v6.5 mega-premium, Apple-like dark)
  ...kPremiumInfos.where((i) => i.group == 2), // midnight/amethyst/emerald/abyss/espresso
];

MapStyleInfo? mapStyleInfo(MapStyle s) {
  for (final i in kMapStyleCatalog) {
    if (i.style == s) return i;
  }
  return null;
}
