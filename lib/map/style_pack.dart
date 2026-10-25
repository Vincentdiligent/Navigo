/// Hosted premium basemap packs (v5.1).
///
/// The v3 lesson: one wrong field in a hand-rolled style document
/// (`sprite: []`) made MapLibre reject the whole style — the user saw a
/// solid background forever, with no route, no pins, no labels.
///
/// v5.1 policy: every MAP THEME is a complete style document served by its
/// provider (or a paint-only recolor of one, for Forest):
///   • Classic   — OpenFreeMap "Liberty": 111 professional layers, real POI
///     sprites, road shields, tunnels, bridges and a native `building-3d`
///     fill-extrusion. The closest thing to Google Maps cartography that
///     is fully free (no key, no registration).
///   • Graphite  — CARTO "Positron": premium light-gray minimalism.
///   • Noir      — CARTO "Dark Matter": premium deep-black basemap.
///   • Forest    — Liberty fetched once and repainted into a premium sage
///     palette. ONLY existing `paint` values are overridden — the style
///     schema is untouched, so MapLibre validity holds (the v3 lesson).
///
/// v5.2 PREMIUM RECOLORS (the user's ask: "используй карту классика, чтобы
/// модифицировать её под разные темы и цвета"): TEN additional map themes
/// (5 dark + 5 light) are generated FROM THE CLASSIC DOCUMENT ITSELF.
/// Liberty is fetched once; for every premium theme every color literal in
/// every paint property (including colors nested inside interpolate /
/// match expressions) is remapped through a hand-tuned palette table
/// covering the FULL inventory of Liberty's 43 color literals. The schema,
/// sources, layers, sprites and glyphs are untouched — only colors change —
/// so the result keeps 100% of Classic's cartography (3D buildings, POI
/// hit-testing, road hierarchy) while looking like a completely different
/// premium basemap.
///   • Satellite — minimal raster-only document: Esri World Imagery +
///     CARTO Voyager label overlay (Google-style hybrid).
///   • Relief    — minimal raster-only document: OpenTopoMap (contours +
///     hillshading baked in).
///   • Fallback  — minimal raster-only document (CARTO Voyager). Used when
///     the primary style does not finish loading.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_state.dart';
import 'apple_docs.dart';

const String kStyleLiberty = 'https://tiles.openfreemap.org/styles/liberty';
const String kStylePositron =
    'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';
const String kStyleDarkMatter =
    'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json';

/// v6.3 «style bake-off»: OSM Bright on the SAME keyless OpenFreeMap
/// hosting as Classic — verified live (HTTP 200, 119 layers; the
/// label_* / poi_r* / highway-name-* id family matches Liberty verbatim,
/// so the shared POI hit-test set works here unmodified). Protomaps was
/// probed too but serves 403 for both styles and tiles without a token,
/// so it stays out until the user provides one.
const String kStyleBright = 'https://tiles.openfreemap.org/styles/bright';

/// A resolved basemap for the current settings.
class StylePack {
  const StylePack({
    required this.styleString,
    this.poiLayerIds = const [],
    this.vector = false,
    this.fallback = false,
  });

  /// URL of a hosted style, or an inline JSON document (starts with '{').
  final String styleString;

  /// Vector layers worth hit-testing for a named feature on tap.
  final List<String> poiLayerIds;

  /// Vector style → POI tap and the 3D-buildings toggle are meaningful.
  final bool vector;

  /// Simplified raster mode (after a failed primary load).
  final bool fallback;
}

/// Liberty's hit-test layers, most specific first (verified against the
/// live style: 111 layers, ids below exist).
const List<String> kLibertyPoiLayers = [
  'poi_r1',
  'poi_r7',
  'poi_r20',
  'poi_transit',
  'airport',
  'label_city_capital',
  'label_city',
  'label_town',
  'label_village',
  'label_other',
  'highway-name-major',
  'highway-name-minor',
  'water_name_point_label',
];

StylePack packFor(MapStyle type) => switch (type) {
  MapStyle.classic => StylePack(
    // v6.4: the processed document (cartography fix + uncapped 2D
    // buildings) once fetched; the hosted URL stays the boot fallback.
    styleString: _classicDoc ?? kStyleLiberty,
    poiLayerIds: kLibertyPoiLayers,
    vector: true,
  ),
  MapStyle.graphite => const StylePack(
    styleString: kStylePositron,
    vector: true,
  ),
  MapStyle.noir => const StylePack(styleString: kStyleDarkMatter, vector: true),
  // v6.3: OSM Bright (OpenFreeMap) — the user's side-by-side style
  // comparison; same OpenMapTiles schema → same POI hit-test set.
  // v6.4: same processed-document path as Classic.
  MapStyle.bright => StylePack(
    styleString: _brightDoc ?? kStyleBright,
    poiLayerIds: kLibertyPoiLayers,
    vector: true,
  ),
  // v6.5 mega-premium cartographies (Atlas / Onyx): complete
  // Apple-Maps-like documents, see apple_docs.dart. Inline JSON →
  // instant (no probe, no watchdog blindness); chips register at load.
  MapStyle.silk => const StylePack(
    styleString: kAppleLightDoc,
    poiLayerIds: kApplePoiLayers,
    vector: true,
  ),
  MapStyle.onyx => const StylePack(
    styleString: kAppleDarkDoc,
    poiLayerIds: kApplePoiLayers,
    vector: true,
  ),
  MapStyle.forest => StylePack(
    styleString: _forestDoc ?? kStyleLiberty,
    poiLayerIds: kLibertyPoiLayers,
    vector: true,
  ),
  MapStyle.satellite => StylePack(
    styleString: _satelliteHybridDoc ?? _satelliteDoc(),
    // The hybrid carries Liberty's real symbol layers → POI tap works
    // there too (the Esri-only doc simply returns no named features).
    poiLayerIds: _satelliteHybridDoc != null ? kLibertyPoiLayers : const [],
    vector: _satelliteHybridDoc != null,
  ),
  MapStyle.relief => StylePack(styleString: _reliefDoc()),
  // v5.2 premium recolors: the repainted Liberty document when ready,
  // plain Classic otherwise (hot-swapped the moment the doc exists).
  _ => StylePack(
    styleString: _premiumDocs[type] ?? kStyleLiberty,
    poiLayerIds: kLibertyPoiLayers,
    vector: true,
  ),
};

StylePack get fallbackPack =>
    StylePack(styleString: _fallbackDoc(), fallback: true);

/// True when the pack for [type] is fully resolved (inline doc generated
/// or a plain hosted URL). The map widget uses this in its style signature
/// so a late-arriving recolored doc hot-swaps in without a restart.
bool packReady(MapStyle type) => switch (type) {
  MapStyle.forest => forestReady,
  MapStyle.satellite => satelliteReady,
  MapStyle.classic ||
  MapStyle.graphite ||
  MapStyle.noir ||
  MapStyle.bright ||
  MapStyle.relief ||
  MapStyle.silk ||
  MapStyle.onyx => true,
  _ => _premiumDocs.containsKey(type),
};

/// True when the current pack is an INLINE JSON document (instant probe,
/// no network needed to validate it).
bool styleDocInline(MapStyle type) => packFor(type).styleString.startsWith('{');

// ── Shared Liberty fetch (one download serves Forest + 10 recolors +
//    the satellite label set) ─────────────────────────────────────────────

String? _libertyRaw;

Future<String?> ensureLibertyRaw() async {
  if (_libertyRaw != null) return _libertyRaw;
  try {
    final res = await http
        .get(Uri.parse(kStyleLiberty))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    _libertyRaw = res.body;
  } catch (_) {
    return null;
  }
  return _libertyRaw;
}

// ── v6.4 CARTOGRAPHY RULE («надо точно сделать как правило по цветам») ───

/// OpenMapTiles serves GENERALIZED landcover below z13 — a single fat grass
/// polygon can swallow a whole city center, so Bordeaux (and every city)
/// reads GREEN at ~2 km altitude. The rule: generalized nature (grass /
/// wood) must not paint urban fabric — it appears only where street-level
/// data is precise. Real OSM parks (precise polygons) keep their zooms.
/// Schema-safe: only a `minzoom` NUMBER moves.
void _applyCartographyFix(Map<String, dynamic> doc) {
  const clamp = <String, double>{
    'landcover_grass': 13.0,
    'landcover_wood': 12.0,
  };
  final layers = doc['layers'] as List? ?? const [];
  for (final l in layers) {
    if (l is! Map<String, dynamic>) continue;
    final target = clamp[l['id']];
    if (target == null) continue;
    final cur = (l['minzoom'] as num?)?.toDouble() ?? 0.0;
    if (cur < target) l['minzoom'] = target;
  }
}

// ── v6.4: Classic & Bright run the PROCESSED documents ─────────────────────

String? _classicDoc;

/// True once Classic's processed document has been built.
bool get classicReady => _classicDoc != null;

/// Classic = the Liberty document + the v5.4 building-uncap (the hosted
/// URL still caps 2D buildings at z14 — houses vanished when 3D was off)
/// + the v6.4 cartography fix. No colors change — Classic stays Classic.
Future<void> ensureClassicStyle() async {
  if (_classicDoc != null) return;
  final raw = await ensureLibertyRaw();
  if (raw == null) return;
  try {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    _uncapBuildingLayer(doc);
    _applyCartographyFix(doc);
    _classicDoc = jsonEncode(doc);
  } catch (_) {
    _classicDoc = null; // the hosted URL keeps serving
  }
}

String? _brightRaw;

Future<String?> ensureBrightRaw() async {
  if (_brightRaw != null) return _brightRaw;
  try {
    final res = await http
        .get(Uri.parse(kStyleBright))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    _brightRaw = res.body;
  } catch (_) {
    return null;
  }
  return _brightRaw;
}

String? _brightDoc;

/// True once Bright's processed document has been built.
bool get brightReady => _brightDoc != null;

/// Bright gets the same surgery as Classic (it shares Liberty's schema).
Future<void> ensureBrightStyle() async {
  if (_brightDoc != null) return;
  final raw = await ensureBrightRaw();
  if (raw == null) return;
  try {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    _uncapBuildingLayer(doc);
    _applyCartographyFix(doc);
    _brightDoc = jsonEncode(doc);
  } catch (_) {
    _brightDoc = null;
  }
}

// ── Forest: paint-only recolor of Liberty (premium sage palette) ──────────

String? _forestDoc;

/// True once the Forest document has been fetched and repainted.
bool get forestReady => _forestDoc != null;

/// Fetches Liberty once and re-paints landcover paints into the Forest
/// palette. ONLY existing `paint` properties are overridden — no schema
/// changes, so the document stays valid MapLibre (the v3 lesson). On any
/// failure the map simply stays Classic — never blank.
/// v5.4 BUILDINGS FIX (user report: «при зуме дома не видны»): Liberty
/// caps the FLAT `building` fill layer at maxzoom 14 — above that, houses
/// exist ONLY as the `building-3d` extrusion. Whenever the extrusion is
/// hidden (3D toggle off, native hiccup), zooming in shows NO buildings at
/// all. Removing the cap makes the 2D footprints render from z13 upward,
/// forever, in every theme.
void _uncapBuildingLayer(Map<String, dynamic> doc) {
  final layers = doc['layers'] as List? ?? const [];
  for (final l in layers) {
    if (l is Map<String, dynamic> && (l['id'] ?? '') == 'building') {
      l.remove('maxzoom');
    }
  }
}

/// v5.6 CONTINENT FIX (the user: «при дезумировании вместо тёмного
/// континенты светлеют! хотя каждая тема должна соответствовать по цвету
/// во всех слоях»): Liberty ships a Natural Earth SHADED-RELIEF RASTER
/// layer (source ne2_shaded, layer 'natural_earth', opacity 0.6 → 0.1 up
/// to z7) that is visible at LOW zoom exactly when the vector landcover
/// thins out. A color remap cannot repaint raster IMAGES — so every dark
/// recolor showed LIGHT beige continents as soon as the user zoomed out.
/// The theme's own background layer already paints the land — the raster
/// underlay is redundant: remove layer + source so the palette holds at
/// EVERY zoom level.
void _stripNaturalEarth(Map<String, dynamic> doc) {
  final layers = doc['layers'] as List? ?? const [];
  doc['layers'] = [
    for (final l in layers)
      if (l is Map<String, dynamic> && (l['id'] ?? '') != 'natural_earth') l,
  ];
  (doc['sources'] as Map<String, dynamic>?)?.remove('ne2_shaded');
}

Future<void> ensureForestStyle() async {
  if (_forestDoc != null) return;
  final raw = await ensureLibertyRaw();
  if (raw == null) return;
  try {
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    _uncapBuildingLayer(doc);
    _stripNaturalEarth(doc); // v5.6: one palette at every zoom
    _applyCartographyFix(doc); // v6.4: no green city centers
    final layers = (doc['layers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    for (final l in layers) {
      final paint = l['paint'];
      if (paint is! Map<String, dynamic>) continue;
      final id = ((l['id'] ?? '') as String).toLowerCase();
      final type = (l['type'] ?? '') as String;
      if (type == 'background') {
        paint['background-color'] = '#e9efe2';
        continue;
      }
      if (type != 'fill' || !paint.containsKey('fill-color')) continue;
      String? c;
      if (id.contains('wood') || id.contains('forest')) {
        c = '#b7d4a4';
      } else if (id.contains('grass')) {
        c = '#c9e0b6';
      } else if (id.contains('park') ||
          id.contains('nature') ||
          id.contains('golf')) {
        c = '#c4dda9';
      } else if (id.contains('agricultur') ||
          id.contains('farmland') ||
          id.contains('farmyard')) {
        c = '#e2ecce';
      } else if (id.contains('cemetery') || id.contains('burial')) {
        c = '#d3e0c6';
      } else if (id.contains('residential')) {
        c = '#e9e8dc';
      } else if (id.contains('landcover')) {
        // Skip snow/rock: they must stay pale/gray.
        if (!id.contains('ice') &&
            !id.contains('glacier') &&
            !id.contains('snow') &&
            !id.contains('rock')) {
          c = '#cde0bb';
        }
      } else if (id.contains('landuse')) {
        c = '#e4e9d4';
      }
      if (c != null) paint['fill-color'] = c;
    }
    _forestDoc = jsonEncode(doc);
  } catch (_) {
    _forestDoc = null; // fall back to plain Liberty
  }
}

// ── v5.2 Premium recolors of Classic (Liberty) ─────────────────────────────
//
// A tiny color algebra + the complete mapping table of Liberty's color
// literals (extracted from the live style: 43 distinct literals, listed in
// _libertyColorMap). Every paint color — including literals nested inside
// interpolate/match expressions — is remapped; everything else (schema,
// layers, sources, sprites, glyphs, zoom functions) passes through
// untouched, so MapLibre validity is preserved by construction.

/// An sRGB color with alpha and just enough math for cartographic palettes.
class Clr {
  const Clr(this.r, this.g, this.b, [this.a = 1]);
  final int r, g, b;
  final double a;

  static int _ch(String s) => int.parse(s, radix: 16);
  static String _h(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');

  /// Parses every CSS color form Liberty uses: #rgb, #rrggbb, rgb()/rgba(),
  /// hsl()/hsla(). Returns null for anything else.
  static Clr? parse(String raw) {
    final s = raw.trim().toLowerCase().replaceAll(' ', '');
    if (s.startsWith('#')) {
      final h = s.substring(1);
      return switch (h.length) {
        3 => Clr(_ch(h[0] * 2), _ch(h[1] * 2), _ch(h[2] * 2)),
        6 => Clr(
          _ch(h.substring(0, 2)),
          _ch(h.substring(2, 4)),
          _ch(h.substring(4, 6)),
        ),
        8 => Clr(
          _ch(h.substring(0, 2)),
          _ch(h.substring(2, 4)),
          _ch(h.substring(4, 6)),
          int.parse(h.substring(6, 8), radix: 16) / 255,
        ),
        _ => null,
      };
    }
    final m = RegExp(r'^(rgba?|hsla?)\(([^)]*)\)$').firstMatch(s);
    if (m == null) return null;
    final fn = m.group(1)!;
    final parts = m.group(2)!.split(',');
    if (fn.startsWith('rgb')) {
      return Clr(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
        parts.length > 3 ? double.parse(parts[3]) : 1,
      );
    }
    // hsl(h,s%,l%[,a])
    final h = double.parse(parts[0]);
    final sat = double.parse(parts[1].replaceAll('%', '')) / 100;
    final l = double.parse(parts[2].replaceAll('%', '')) / 100;
    final a = parts.length > 3 ? double.parse(parts[3]) : 1.0;
    final c = (1 - (2 * l - 1).abs()) * sat;
    final hp = (h % 360) / 60;
    final x = c * (1 - (hp % 2 - 1).abs());
    final mm = l - c / 2;
    final (r1, g1, b1) = switch (hp.floor()) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    return Clr(
      ((r1 + mm) * 255).round(),
      ((g1 + mm) * 255).round(),
      ((b1 + mm) * 255).round(),
      a,
    );
  }

  String enc() {
    if (a >= 0.999) return '#${_h(r)}${_h(g)}${_h(b)}';
    final av = a.toStringAsFixed(3);
    return 'rgba($r,$g,$b,${av.endsWith('0') ? a.toStringAsFixed(2) : av})';
  }

  Clr withAlpha(double v) => Clr(r, g, b, v.clamp(0.0, 1.0));

  /// t = 0 → this, t = 1 → [o]. Alpha mixes too.
  Clr mix(Clr o, double t) => Clr(
    (r + (o.r - r) * t).round(),
    (g + (o.g - g) * t).round(),
    (b + (o.b - b) * t).round(),
    a + (o.a - a) * t,
  );

  double get lum => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  Clr get gray {
    final l = (lum * 255).round();
    return Clr(l, l, l, a);
  }

  /// Dark-theme safety net for a color that is not in the mapping table:
  /// compress it into the map's dark value range so nothing stays blinding.
  Clr darkened(int landLum) {
    final target = (landLum + lum * 46).round().clamp(0, 255);
    final g = gray;
    final k = target / (g.r == 0 ? 1 : g.r);
    final scaled = Clr(
      (g.r * k).round(),
      (g.r * k).round(),
      (g.r * k).round(),
      a,
    );
    return scaled.mix(this, 0.25); // keep a hint of the original hue
  }
}

/// A hand-tuned premium palette. Core colors are explicit; the remaining
/// ~25 Liberty literals are derived from them with consistent color math,
/// which keeps every theme coherent.
class PremiumPalette {
  const PremiumPalette({
    required this.dark,
    required this.land,
    required this.water,
    required this.park,
    required this.building,
    required this.road,
    required this.roadCasing,
    required this.highway,
    required this.highwayCasing,
    required this.major,
    required this.rail,
    required this.boundary,
    required this.label,
    required this.labelHalo,
    required this.poiLabel,
    required this.roadLabel,
    required this.waterLabel,
    this.residential,
  });

  final bool dark;
  final Clr land, water, park, building;
  final Clr road, roadCasing, highway, highwayCasing, major, rail;
  final Clr boundary, label, labelHalo, poiLabel, roadLabel, waterLabel;

  /// Residential landuse — defaults to a half-step between land & building.
  Clr get resolvedResidential =>
      residential ?? land.mix(building, dark ? 0.55 : 0.45);
  final Clr? residential;
}

// The 5 premium DARK recolors.
const Map<MapStyle, PremiumPalette> kPremiumPalettes = {
  // Полночь: глубокий чернильно-синий.
  MapStyle.midnight: PremiumPalette(
    dark: true,
    land: Clr(13, 22, 38),
    water: Clr(21, 47, 76),
    park: Clr(21, 47, 39),
    building: Clr(26, 39, 64),
    road: Clr(38, 51, 73),
    roadCasing: Clr(15, 25, 43),
    highway: Clr(51, 80, 127),
    highwayCasing: Clr(15, 25, 48),
    major: Clr(42, 61, 92),
    rail: Clr(34, 48, 70),
    boundary: Clr(58, 76, 110),
    label: Clr(201, 214, 236),
    labelHalo: Clr(13, 22, 38),
    poiLabel: Clr(147, 165, 196),
    roadLabel: Clr(118, 136, 168),
    waterLabel: Clr(77, 127, 180),
  ),
  // Аметист: тёмный фиолет.
  MapStyle.amethyst: PremiumPalette(
    dark: true,
    land: Clr(21, 16, 33),
    water: Clr(42, 33, 83),
    park: Clr(34, 28, 56),
    building: Clr(36, 27, 58),
    road: Clr(52, 42, 76),
    roadCasing: Clr(28, 21, 48),
    highway: Clr(91, 71, 148),
    highwayCasing: Clr(34, 25, 56),
    major: Clr(69, 53, 105),
    rail: Clr(44, 35, 66),
    boundary: Clr(69, 55, 102),
    label: Clr(216, 205, 242),
    labelHalo: Clr(21, 16, 33),
    poiLabel: Clr(167, 149, 209),
    roadLabel: Clr(141, 123, 184),
    waterLabel: Clr(122, 104, 201),
  ),
  // Изумруд: тёмный изумрудно-зелёный.
  MapStyle.emerald: PremiumPalette(
    dark: true,
    land: Clr(13, 23, 19),
    water: Clr(17, 51, 59),
    park: Clr(21, 50, 31),
    building: Clr(24, 39, 32),
    road: Clr(36, 56, 45),
    roadCasing: Clr(15, 28, 21),
    highway: Clr(46, 129, 97),
    highwayCasing: Clr(14, 26, 19),
    major: Clr(37, 87, 63),
    rail: Clr(30, 47, 38),
    boundary: Clr(45, 76, 60),
    label: Clr(198, 226, 208),
    labelHalo: Clr(13, 23, 19),
    poiLabel: Clr(136, 184, 154),
    roadLabel: Clr(109, 156, 130),
    waterLabel: Clr(62, 143, 151),
  ),
  // Бездна: почти чёрный сине-циановый.
  MapStyle.abyss: PremiumPalette(
    dark: true,
    land: Clr(8, 16, 25),
    water: Clr(13, 43, 60),
    park: Clr(13, 38, 32),
    building: Clr(16, 29, 41),
    road: Clr(28, 50, 66),
    roadCasing: Clr(10, 20, 32),
    highway: Clr(26, 94, 125),
    highwayCasing: Clr(9, 19, 32),
    major: Clr(22, 70, 86),
    rail: Clr(21, 38, 52),
    boundary: Clr(38, 80, 99),
    label: Clr(184, 216, 232),
    labelHalo: Clr(8, 16, 25),
    poiLabel: Clr(126, 168, 192),
    roadLabel: Clr(98, 142, 166),
    waterLabel: Clr(46, 131, 168),
  ),
  // Эспрессо: тёплый тёмно-коричневый.
  MapStyle.espresso: PremiumPalette(
    dark: true,
    land: Clr(23, 18, 13),
    water: Clr(36, 51, 60),
    park: Clr(34, 43, 22),
    building: Clr(36, 29, 21),
    road: Clr(51, 41, 31),
    roadCasing: Clr(28, 22, 16),
    highway: Clr(125, 90, 46),
    highwayCasing: Clr(27, 18, 10),
    major: Clr(87, 69, 44),
    rail: Clr(44, 35, 24),
    boundary: Clr(74, 60, 42),
    label: Clr(230, 217, 198),
    labelHalo: Clr(23, 18, 13),
    poiLabel: Clr(181, 164, 139),
    roadLabel: Clr(153, 135, 108),
    waterLabel: Clr(95, 135, 148),
  ),

  // The 5 premium LIGHT recolors.
  // Жемчуг: светлая слоновая кость.
  MapStyle.pearl: PremiumPalette(
    dark: false,
    land: Clr(244, 242, 237),
    water: Clr(168, 207, 227),
    park: Clr(205, 228, 189),
    building: Clr(229, 226, 216),
    road: Clr(255, 255, 255),
    roadCasing: Clr(220, 214, 200),
    highway: Clr(244, 196, 118),
    highwayCasing: Clr(220, 174, 106),
    major: Clr(248, 231, 169),
    rail: Clr(203, 198, 186),
    boundary: Clr(179, 172, 157),
    label: Clr(75, 74, 69),
    labelHalo: Clr(253, 252, 249),
    poiLabel: Clr(126, 123, 114),
    roadLabel: Clr(144, 139, 127),
    waterLabel: Clr(109, 157, 194),
  ),
  // Песок: тёплый бежевый атлас.
  MapStyle.sand: PremiumPalette(
    dark: false,
    land: Clr(242, 235, 218),
    water: Clr(165, 203, 221),
    park: Clr(203, 225, 174),
    building: Clr(233, 221, 197),
    road: Clr(253, 249, 238),
    roadCasing: Clr(216, 204, 178),
    highway: Clr(239, 180, 94),
    highwayCasing: Clr(217, 161, 78),
    major: Clr(244, 222, 158),
    rail: Clr(207, 196, 172),
    boundary: Clr(185, 172, 144),
    label: Clr(93, 83, 64),
    labelHalo: Clr(249, 243, 229),
    poiLabel: Clr(139, 128, 105),
    roadLabel: Clr(153, 139, 110),
    waterLabel: Clr(106, 154, 180),
  ),
  // Арктика: холодный ледяной светлый.
  MapStyle.arctic: PremiumPalette(
    dark: false,
    land: Clr(237, 241, 244),
    water: Clr(166, 210, 229),
    park: Clr(201, 223, 209),
    building: Clr(220, 228, 233),
    road: Clr(255, 255, 255),
    roadCasing: Clr(203, 215, 221),
    highway: Clr(133, 188, 217),
    highwayCasing: Clr(105, 162, 193),
    major: Clr(213, 231, 240),
    rail: Clr(193, 203, 208),
    boundary: Clr(159, 177, 186),
    label: Clr(62, 74, 82),
    labelHalo: Clr(247, 250, 252),
    poiLabel: Clr(111, 130, 141),
    roadLabel: Clr(125, 145, 156),
    waterLabel: Clr(92, 146, 180),
  ),
  // Роза: пастельная пудровая.
  MapStyle.rose: PremiumPalette(
    dark: false,
    land: Clr(246, 237, 235),
    water: Clr(174, 211, 226),
    park: Clr(210, 227, 192),
    building: Clr(236, 220, 215),
    road: Clr(255, 250, 248),
    roadCasing: Clr(226, 202, 197),
    highway: Clr(233, 162, 140),
    highwayCasing: Clr(214, 136, 113),
    major: Clr(244, 215, 191),
    rail: Clr(213, 189, 184),
    boundary: Clr(197, 165, 159),
    label: Clr(93, 68, 64),
    labelHalo: Clr(251, 242, 239),
    poiLabel: Clr(148, 118, 111),
    roadLabel: Clr(162, 132, 124),
    waterLabel: Clr(109, 154, 186),
  ),
  // Мята: свежий светло-зелёный.
  MapStyle.mint: PremiumPalette(
    dark: false,
    land: Clr(237, 244, 236),
    water: Clr(163, 210, 214),
    park: Clr(195, 226, 182),
    building: Clr(220, 231, 217),
    road: Clr(255, 255, 255),
    roadCasing: Clr(203, 219, 202),
    highway: Clr(138, 199, 162),
    highwayCasing: Clr(98, 169, 130),
    major: Clr(210, 233, 216),
    rail: Clr(194, 208, 194),
    boundary: Clr(160, 181, 161),
    label: Clr(63, 82, 68),
    labelHalo: Clr(246, 250, 245),
    poiLabel: Clr(113, 138, 115),
    roadLabel: Clr(127, 151, 127),
    waterLabel: Clr(85, 152, 158),
  ),
};

const List<MapStyle> kPremiumStyles = [
  MapStyle.midnight,
  MapStyle.amethyst,
  MapStyle.emerald,
  MapStyle.abyss,
  MapStyle.espresso,
  MapStyle.pearl,
  MapStyle.sand,
  MapStyle.arctic,
  MapStyle.rose,
  MapStyle.mint,
];

final Map<MapStyle, String> _premiumDocs = {};

/// True once the recolored document for [type] has been generated.
bool premiumReady(MapStyle type) => _premiumDocs.containsKey(type);

/// Fetches Classic (Liberty) ONCE and generates the repainted document for
/// every premium theme that is not ready yet. On network failure nothing
/// changes — premium themes simply stay on plain Classic until a later
/// call succeeds (same contract as Forest).
Future<void> ensureAllPremiumStyles() async {
  final todo = kPremiumStyles
      .where((s) => !_premiumDocs.containsKey(s))
      .toList();
  if (todo.isEmpty) return;
  final raw = await ensureLibertyRaw();
  if (raw == null) return;
  for (final s in todo) {
    try {
      final doc = jsonDecode(raw) as Map<String, dynamic>;
      _uncapBuildingLayer(doc); // v5.4: 2D houses visible at EVERY zoom
      _stripNaturalEarth(doc); // v5.6: no light continents when zooming out
      _applyCartographyFix(doc); // v6.4: no green city centers
      _recolorLiberty(doc, kPremiumPalettes[s]!);
      _premiumDocs[s] = jsonEncode(doc);
    } catch (_) {
      // One theme failing must not block the others.
    }
  }
}

// ── v6.6: EVERY EXISTING PALETTE ON THE NEW ENGINE ────────────────────────
//
// The user loved the v6.5 Atlas/Onyx cartography («две новые карты топ!»)
// and asked for ALL his colors on that rendering: «мне нужно все наши цвета
// карт перенести на новые!!». The PREMIUM RENDER FAMILY does exactly that:
// every vector theme is drawn by the Apple-style documents (same road
// hierarchy, same POI chips, same label ladder) repainted into the theme's
// OWN palette. The base documents are inline constants → the repaint is
// SYNCHRONOUS, offline-proof and instant — no fetch, no probe, no watchdog.

/// Hand-tuned palettes for the themes that predate [PremiumPalette] — every
/// core value sampled from the REAL style documents (hosted Liberty /
/// Positron / Dark Matter / the catalog previews). The Atlas recolor derives
/// the remaining ~30 semantic slots from these.
const Map<MapStyle, PremiumPalette> kAtlasBasePalettes = {
  // Классика (Liberty): кремовая земля, охристые магистрали.
  MapStyle.classic: PremiumPalette(
    dark: false,
    land: Clr(248, 244, 240),
    water: Clr(160, 200, 240),
    park: Clr(216, 232, 200),
    building: Clr(224, 222, 217),
    road: Clr(255, 255, 255),
    roadCasing: Clr(207, 205, 202),
    highway: Clr(255, 204, 136),
    highwayCasing: Clr(233, 172, 119),
    major: Clr(255, 244, 198),
    rail: Clr(187, 187, 187),
    boundary: Clr(105, 104, 106),
    label: Clr(51, 51, 51),
    labelHalo: Clr(255, 255, 255),
    poiLabel: Clr(102, 102, 102),
    roadLabel: Clr(180, 158, 136),
    waterLabel: Clr(116, 174, 233),
  ),
  // Графит (Positron): светло-серый минимализм.
  MapStyle.graphite: PremiumPalette(
    dark: false,
    land: Clr(250, 250, 248),
    water: Clr(202, 214, 222),
    park: Clr(224, 232, 221),
    building: Clr(232, 232, 230),
    road: Clr(255, 255, 255),
    roadCasing: Clr(201, 201, 196),
    highway: Clr(185, 189, 194),
    highwayCasing: Clr(168, 173, 179),
    major: Clr(237, 237, 235),
    rail: Clr(204, 204, 204),
    boundary: Clr(192, 192, 192),
    label: Clr(77, 77, 77),
    labelHalo: Clr(250, 250, 248),
    poiLabel: Clr(130, 130, 130),
    roadLabel: Clr(148, 148, 148),
    waterLabel: Clr(140, 166, 184),
  ),
  // Нуар (Dark Matter): глубокий чёрный.
  MapStyle.noir: PremiumPalette(
    dark: true,
    land: Clr(14, 20, 27),
    water: Clr(15, 34, 51),
    park: Clr(18, 38, 26),
    building: Clr(23, 23, 27),
    road: Clr(51, 51, 61),
    roadCasing: Clr(8, 8, 9),
    highway: Clr(78, 90, 110),
    highwayCasing: Clr(42, 50, 64),
    major: Clr(58, 65, 72),
    rail: Clr(58, 58, 68),
    boundary: Clr(90, 98, 110),
    label: Clr(232, 234, 237),
    labelHalo: Clr(14, 20, 27),
    poiLabel: Clr(154, 162, 174),
    roadLabel: Clr(124, 135, 148),
    waterLabel: Clr(93, 122, 150),
  ),
  // Лес: шалфейно-зелёная классика.
  MapStyle.forest: PremiumPalette(
    dark: false,
    land: Clr(233, 239, 226),
    water: Clr(169, 211, 232),
    park: Clr(183, 212, 164),
    building: Clr(227, 222, 210),
    road: Clr(253, 253, 246),
    roadCasing: Clr(201, 205, 180),
    highway: Clr(232, 180, 94),
    highwayCasing: Clr(209, 154, 74),
    major: Clr(243, 206, 123),
    rail: Clr(184, 184, 168),
    boundary: Clr(154, 164, 142),
    label: Clr(62, 74, 56),
    labelHalo: Clr(244, 247, 238),
    poiLabel: Clr(110, 122, 100),
    roadLabel: Clr(138, 144, 120),
    waterLabel: Clr(94, 143, 184),
  ),
  // Осм Брайт: тёплый крем с оранжевыми магистралями.
  MapStyle.bright: PremiumPalette(
    dark: false,
    land: Clr(248, 244, 240),
    water: Clr(170, 211, 223),
    park: Clr(205, 227, 184),
    building: Clr(223, 217, 208),
    road: Clr(255, 255, 255),
    roadCasing: Clr(214, 204, 192),
    highway: Clr(240, 149, 111),
    highwayCasing: Clr(216, 115, 74),
    major: Clr(255, 217, 168),
    rail: Clr(196, 187, 178),
    boundary: Clr(158, 148, 138),
    label: Clr(58, 52, 48),
    labelHalo: Clr(255, 253, 251),
    poiLabel: Clr(122, 113, 106),
    roadLabel: Clr(156, 140, 128),
    waterLabel: Clr(91, 135, 166),
  ),
};

/// The palette of any vector theme for the Atlas engine. silk/onyx ARE the
/// engine's natives; satellite/relief have none — they stay raster.
PremiumPalette? atlasPaletteOf(MapStyle s) =>
    kAtlasBasePalettes[s] ?? kPremiumPalettes[s];

// ── ATLAS DECORATIONS (v6.6.1) ──────────────────────────────────────────────
// The Atlas family draws EVERY color theme with the same Apple cartography,
// so what is painted ON TOP of the basemap must follow the active palette too:
// POI chips (body, ring, glyph) and the route line trio. Pure color math —
// no fetch, no document rewrite, nothing that can break the style schema.

/// The native silk/onyx documents expressed as palettes, so decorations read
/// ONE source of truth instead of special-casing the two originals.
const Map<MapStyle, PremiumPalette> kAtlasNativePalettes = {
  MapStyle.silk: PremiumPalette(
    dark: false,
    land: Clr(242, 242, 247),
    water: Clr(144, 192, 224),
    park: Clr(212, 234, 206),
    building: Clr(224, 224, 228),
    road: Clr(255, 255, 255),
    roadCasing: Clr(200, 200, 204),
    highway: Clr(232, 168, 48),
    highwayCasing: Clr(192, 144, 48),
    major: Clr(245, 224, 160),
    rail: Clr(176, 176, 180),
    boundary: Clr(160, 160, 168),
    label: Clr(28, 28, 30),
    labelHalo: Clr(242, 242, 247),
    poiLabel: Clr(142, 142, 147),
    roadLabel: Clr(112, 112, 118),
    waterLabel: Clr(40, 120, 176),
  ),
  MapStyle.onyx: PremiumPalette(
    dark: true,
    land: Clr(28, 28, 30),
    water: Clr(15, 42, 56),
    park: Clr(29, 39, 29),
    building: Clr(44, 44, 46),
    road: Clr(56, 56, 58),
    roadCasing: Clr(22, 22, 24),
    highway: Clr(84, 69, 48),
    highwayCasing: Clr(10, 10, 12),
    major: Clr(74, 68, 50),
    rail: Clr(58, 58, 60),
    boundary: Clr(90, 90, 94),
    label: Clr(235, 235, 245),
    labelHalo: Clr(28, 28, 30),
    poiLabel: Clr(152, 152, 160),
    roadLabel: Clr(126, 126, 134),
    waterLabel: Clr(61, 126, 166),
  ),
};

/// The palette the ACTIVE basemap paints with — every vector theme, silk and
/// onyx included. Null only for imagery (satellite / relief), which has no
/// palette of its own to inherit.
PremiumPalette? atlasRenderPaletteOf(MapStyle s) =>
    atlasPaletteOf(s) ?? kAtlasNativePalettes[s];

/// Perceptual distance: a luminance gap PLUS a hue/chroma gap. Luminance
/// alone would call a blue route line and an amber motorway "the same color",
/// which is the one thing a route must never be.
double _atlasSep(Clr a, Clr b) {
  final lum = (a.lum - b.lum).abs() * 2.2;
  final dr = (a.r - b.r) / 255.0;
  final dg = (a.g - b.g) / 255.0;
  final db = (a.b - b.b) / 255.0;
  final rgb = math.sqrt(dr * dr + dg * dg + db * db) / 1.7320508;
  return lum * 0.4 + rgb * 0.6;
}

/// Chip and route cosmetics for one palette.
class AtlasDeco {
  const AtlasDeco({
    required this.dark,
    required this.chipBody,
    required this.chipRing,
    required this.glyphAnchor,
    required this.route,
    required this.routeCasing,
    required this.routeTraveled,
  });

  final bool dark;
  final Clr chipBody, chipRing, glyphAnchor;
  final Clr route, routeCasing, routeTraveled;

  /// A category glyph in the basemap's own key: nudged toward the theme's POI
  /// text color, then forced to stay readable on THIS chip body.
  Clr glyphFor(Clr category) {
    var g = category.mix(glyphAnchor, 0.16);
    if (_atlasSep(g, chipBody) < 0.32) g = g.mix(glyphAnchor, 0.42);
    if (_atlasSep(g, chipBody) < 0.32) g = glyphAnchor;
    return g;
  }
}

/// The decorations for a basemap drawn from [p].
AtlasDeco atlasDecoOf(PremiumPalette p) {
  const white = Clr(255, 255, 255);
  const black = Clr(0, 0, 0);

  // Chips: a light disc on dark palettes (raised off the land), a warm
  // near-white disc on light ones — always one step from the basemap.
  final chipBody = p.dark ? p.land.mix(p.label, 0.20) : white.mix(p.land, 0.10);
  final chipRing = p.dark ? p.label.withAlpha(0.16) : p.label.withAlpha(0.14);
  final glyphAnchor = p.dark
      ? p.label.mix(p.poiLabel, 0.30)
      : p.label.mix(p.poiLabel, 0.55);

  // Route: the signal color that stays furthest from the theme's OWN road
  // colors — blue where possible, amber on blue-dominant palettes (Полночь,
  // Бездна), rose on warm amber ones. The casing is carved out of the
  // basemap, so the line always reads as "the route", never as "a road".
  const candidates = [
    Clr(47, 125, 246), // Apple navigation blue
    Clr(255, 176, 84), // amber
    Clr(232, 80, 140), // rose
  ];
  var route = candidates.first;
  var best = -1.0;
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    final score = [
      p.land,
      p.road,
      p.major,
      p.highway,
    ].map((bg) => _atlasSep(c, bg)).reduce(math.min);
    // Navigation blue is the identity: it only loses when another signal
    // color is CLEARLY better on this palette (blue-dominant themes like
    // Полночь/Бездна take amber, зелёные — rose).
    final margin = i == 0 ? 0.07 : 0.0;
    if (score + margin > best) {
      best = score + margin;
      route = c;
    }
  }
  if (p.dark) route = route.mix(white, 0.12);

  return AtlasDeco(
    dark: p.dark,
    chipBody: chipBody,
    chipRing: chipRing,
    glyphAnchor: glyphAnchor,
    route: route,
    routeCasing: p.dark ? p.land.mix(black, 0.45) : white.mix(p.land, 0.30),
    routeTraveled: p.rail.mix(p.label, 0.22),
  );
}

/// The palette + deco for the current settings, or null when the basemap is
/// imagery or a host-drawn Classic document (then chips and route keep the
/// app look, exactly as before v6.6.1).
({PremiumPalette palette, AtlasDeco deco})? atlasLookFor(
  MapStyle s,
  bool premium,
) {
  if (!premium && s != MapStyle.silk && s != MapStyle.onyx) return null;
  final p = atlasRenderPaletteOf(s);
  if (p == null) return null;
  return (palette: p, deco: atlasDecoOf(p));
}

final Map<MapStyle, String> _atlasDocs = {};

/// The Apple-engine document repainted into [type]'s own palette.
/// Synchronous by construction (inline base documents, pure color math).
StylePack packForAtlas(MapStyle type) {
  if (type == MapStyle.silk || type == MapStyle.onyx) return packFor(type);
  final p = atlasPaletteOf(type);
  if (p == null) return packFor(type); // satellite / relief stay raster
  final doc = _atlasDocs[type] ??= _restyleAppleDoc(
    p.dark ? kAppleDarkDoc : kAppleLightDoc,
    p,
    type,
  );
  return StylePack(
    styleString: doc,
    poiLayerIds: kApplePoiLayers,
    vector: true,
  );
}

/// The image-id namespace of one basemap's chips («a-food» → «a-food~pearl»).
String chipTagFor(MapStyle s) => '~${s.name}';

final Map<String, ({String src, StylePack? tagged})> _familyPacks = {};

/// The pack for the ACTIVE rendering family (v6.6 premium render toggle).
///
/// v6.8.3: every basemap draws its chips under its OWN image ids. All themes
/// used to register `a-food`, `a-cafe`, … and MapLibre keeps the icon it
/// resolved when the tile was first placed — re-adding a name that already
/// exists never reaches the tiles already on screen (the plugin disables
/// synchronous image updates for exactly this reason: maplibre-native#4326).
/// So after a theme switch the NEW basemap kept painting the PREVIOUS one's
/// bitmaps: a light theme wearing the charcoal discs of Оникс until a zoom
/// re-placed the tiles («на светлых темах чипы тёмные, уменьшаю — сразу
/// светлые»). An id no other theme ever owned cannot go stale.
StylePack packForFamily(MapStyle type, bool premium) {
  final key = '${type.name}|${premium ? 1 : 0}';
  final pack = premium ? packForAtlas(type) : packFor(type);
  final hit = _familyPacks[key];
  if (hit != null && identical(hit.src, pack.styleString)) {
    return hit.tagged ?? pack;
  }
  final doc = _tagChipIcons(pack.styleString, chipTagFor(type));
  final tagged = doc == null
      ? null
      : StylePack(
          styleString: doc,
          poiLayerIds: pack.poiLayerIds,
          vector: pack.vector,
          fallback: pack.fallback,
        );
  _familyPacks[key] = (src: pack.styleString, tagged: tagged);
  return tagged ?? pack;
}

/// Rewrites every `icon-image` of an inline document into [tag]'s namespace.
/// Null when the document has no chips in it (a hosted style URL, or
/// Liberty's own sprite names) — then the pack is used untouched.
///
/// NOTHING else in the chip layers is touched: `icon-size`, `text-size`,
/// `text-offset` and placement stay exactly as the backup documents define
/// them (the user, v6.8.5: «чипсы не трогаешь — именно после того как ты их
/// трогаешь идут проблемы»).
String? _tagChipIcons(String doc, String tag) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(doc) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  var found = false;
  for (final layer in (json['layers'] as List? ?? const [])) {
    if (layer is! Map<String, dynamic>) continue;
    final layout = layer['layout'];
    if (layout is! Map<String, dynamic>) continue;
    final icon = layout['icon-image'];
    if (icon == null) continue;
    final next = _tagIconRef(icon, tag);
    if (next == null) continue;
    layout['icon-image'] = next;
    found = true;
  }
  return found ? jsonEncode(json) : null;
}

/// Tagged copy of one `icon-image` expression, or null if it has no `a-*`
/// chip in it. Expressions nest arbitrarily deep (match/coalesce/case), so
/// the walk is generic.
dynamic _tagIconRef(dynamic v, String tag) {
  if (v is String) return v.startsWith('a-') ? '$v$tag' : null;
  if (v is List) {
    dynamic out;
    for (var i = 0; i < v.length; i++) {
      final next = _tagIconRef(v[i], tag);
      if (next == null) continue;
      out ??= List<dynamic>.of(v);
      out[i] = next;
    }
    return out;
  }
  return null;
}

/// Pack readiness per family. Atlas documents are synchronous → every
/// palette theme is ready the first time it is asked for. Imagery
/// (satellite/relief) is never repainted, so it keeps its own rules.
bool packReadyFor(MapStyle type, bool premium) => premium
    ? (type == MapStyle.satellite || type == MapStyle.relief)
          ? packReady(type)
          : (type == MapStyle.silk ||
                type == MapStyle.onyx ||
                atlasPaletteOf(type) != null)
    : packReady(type);

bool styleDocInlineFor(MapStyle type, bool premium) =>
    packForFamily(type, premium).styleString.startsWith('{');

final Map<MapStyle, bool> _familyMatters = {};

/// v6.8: does the render family actually change the DOCUMENT for [type]?
/// Шёлк / Оникс carry their own inline Apple documents and Спутник is never
/// repainted, so for them both families produce the same style. A signature
/// that flips anyway promises a native style reload that never happens — the
/// watchdog then times out and drops the basemap into simplified raster
/// mode («тема включилась, а тайлов нет»).
bool familyMattersFor(MapStyle type) => _familyMatters[type] ??=
    packForFamily(type, true).styleString !=
    packForFamily(type, false).styleString;

/// The semantic vocabulary of the Apple-style documents, derived from one
/// [PremiumPalette]. Every literal in both documents (they share the same
/// layer inventory) maps to one of these roles.
class _AtlasRoles {
  _AtlasRoles(this.p) {
    final black = const Clr(0, 0, 0);
    ice = p.dark
        ? p.land.mix(const Clr(216, 230, 234), 0.12)
        : p.land.mix(const Clr(214, 232, 242), 0.50);
    sand = p.dark
        ? p.land.mix(const Clr(138, 116, 76), 0.20)
        : p.land.mix(const Clr(224, 209, 160), 0.55);
    grass = p.park.mix(p.land, 0.22);
    wood = p.park.mix(p.land, 0.10);
    wetland = p.park.mix(p.water, 0.30);
    residential = p.resolvedResidential;
    commercial = residential.mix(p.building, 0.35);
    industrial = p.land.mix(p.building, 0.55);
    military = p.land.mix(p.building, 0.45);
    hospital = p.dark
        ? p.land.mix(const Clr(112, 62, 74), 0.22)
        : p.land.mix(const Clr(242, 198, 198), 0.30);
    school = p.dark
        ? p.land.mix(const Clr(88, 94, 58), 0.22)
        : p.land.mix(const Clr(233, 235, 196), 0.34);
    cemetery = p.park.mix(p.land, 0.35);
    apron = p.land.mix(p.building, 0.55);
    runway = p.land.mix(p.building, 0.72);
    taxiway = p.land.mix(p.building, 0.62);
    path = p.roadCasing.mix(p.building, 0.30);
    bldOutline = p.dark
        ? p.building.mix(p.label, 0.30)
        : p.building.mix(p.label, 0.26);
    casingWarm = p.roadCasing.mix(p.highwayCasing, 0.45);
    motorLow = p.highway.mix(p.highwayCasing, 0.30);
    motorMid = p.highway.mix(p.highwayCasing, 0.15);
    shieldText = p.highway.mix(p.label, p.dark ? 0.30 : 0.40);
    parkText = p.park.mix(p.label, p.dark ? 0.45 : 0.38);
    boundaryBg = p.dark
        ? p.land.mix(black, 0.45)
        : p.land.mix(const Clr(255, 255, 255), 0.30);
    waterOutline = p.water.mix(p.waterLabel, 0.25);
    stateLine = p.boundary.mix(p.land, 0.30);

    // GLOBAL LITERAL MAP — every remaining literal of the active document.
    byLiteral = p.dark
        ? {
            // Background + every label halo (same literal in the dark doc).
            '1c1c1e': p.land,
            // Label text (all alpha variants).
            'ebebf5': p.label,
            // Landcover / landuse.
            '2a2820': sand, '1e261e': grass, '1a231a': wood, '162022': wetland,
            '202022': residential, '212120': commercial, '1e1e20': industrial,
            '1d271d': p.park, '22201e': hospital, '20201c': school,
            '1b231b': cemetery, '1f1e1b': military,
            // Water.
            '0f2a38': p.water, '0d2535': p.water, '0f2e40': waterOutline,
            // Aeroways.
            '222224': apron, '262628': runway, '242426': taxiway,
            // Paths / rail (rail layers override).
            '3a3a3c': bldOutline,
            // Casings.
            '161618': p.roadCasing, '141416': p.roadCasing,
            '0f0f10': p.roadCasing, '0a0a0c': p.highwayCasing,
            // Roads (minor/service/secondary overridden per layer).
            '38383a': p.road.mix(p.land, 0.12),
            '4a4432': p.major,
            '3a3020': motorLow, '4a3e28': motorMid, '544530': p.highway,
            // Boundaries.
            '000000': boundaryBg, '5a5a5e': p.boundary, '48484a': stateLine,
            // Labels.
            '3d7ea6': p.waterLabel, '3a6e8c': p.waterLabel,
            'e8dfc8': shieldText,
            // POI text.
            '4a8a4a': parkText, '5b8db8': p.waterLabel,
          }
        : {
            // Background + every label halo (same literal in the light doc).
            'f2f2f7': p.land,
            // Label text (all alpha variants).
            '1c1c1e': p.label,
            // Landcover / landuse.
            'e8eef4': ice, 'f0ead6': sand, 'd8edd0': grass, 'c8e0c0': wood,
            'c8ddd8': wetland, 'ededf0': residential, 'f5efe6': commercial,
            'eae8ec': industrial, 'd4eace': p.park, 'f5ece8': hospital,
            'eef0e4': school, 'd8e8d0': cemetery, 'ede8dc': military,
            // Water.
            '90c0e0': p.water, 'a8d4f0': p.water,
            // Aeroways.
            'dcdce0': apron, 'd0d0d4': runway, 'd4d4d8': taxiway,
            // Paths / rail (rail layers override).
            'b0b0b4': path,
            // Casings.
            'c8c8cc': p.roadCasing, 'b8b8bc': p.roadCasing,
            'c0c0c4': p.roadCasing, 'b0a898': casingWarm,
            'c8a850': p.highwayCasing, 'c09030': p.highwayCasing,
            // Roads (minor/service/secondary/primary overridden per layer).
            'e8e8ec': p.road.mix(p.land, 0.5),
            'f8f8fa': p.road, 'ffffff': p.road, 'f4f4f4': p.road,
            'f5e0a0': p.major,
            'f0c060': motorLow, 'edb84a': motorMid, 'e8a830': p.highway,
            // Boundaries.
            'a0a0a8': p.boundary, 'b8b8c0': stateLine,
            // Labels.
            '2878b0': p.waterLabel, '5c4000': shieldText,
            // POI text.
            '2e7d32': parkText, '1565c0': p.waterLabel,
          };

    // PER-LAYER OVERRIDES — the few literals one document shares between
    // DIFFERENT semantic slots (roads vs buildings vs ice). Exact layer ids
    // of both documents (they are generated symmetric).
    final dark = p.dark;
    overrides = {
      'building': {
        if (dark) '2c2c2e': p.building else 'e0e0e4': p.building,
        if (dark) '38383a': bldOutline else 'c8c8cc': bldOutline,
      },
      'building-3d': dark
          ? {
              '2c2c2e': p.building.mix(p.label, 0.05),
              '323234': p.building.mix(p.label, 0.14),
            }
          : {
              'dcdcdf': p.building.mix(p.label, 0.08),
              'd0d0d4': p.building.mix(p.label, 0.18),
            },
      'road-minor': dark ? {'2c2c2e': p.road} : {'ffffff': p.road},
      'road-service': dark ? {'2c2c2e': p.road} : {'f8f8fa': p.road},
      'road-secondary': dark ? {'38383a': p.road} : {'f4f4f4': p.road},
      'road-primary': dark
          ? {'48484a': p.road.mix(p.land, 0.16)}
          : {'f0ede8': p.road.mix(p.land, 0.22)},
      'road-area-pedestrian': dark
          ? {'252527': p.road.mix(p.land, 0.5)}
          : {'e8e8ec': p.road.mix(p.land, 0.5)},
      'road-path': {'b0b0b4': path, '3a3a3c': path},
      'road-rail': {'b8b8bc': p.rail, '3a3a3c': p.rail},
      'road-rail-hatching': {'b8b8bc': p.rail, '3a3a3c': p.rail},
      'aeroway-runway-line': {'b0b0b4': bldOutline, '3a3a3c': bldOutline},
      'landcover-ice': dark ? {'2c2c2e': ice} : {'e8eef4': ice},
    };
  }

  final PremiumPalette p;
  late final Map<String, Clr> byLiteral;
  late final Map<String, Map<String, Clr>> overrides;

  late final Clr ice, sand, grass, wood, wetland, residential, commercial;
  late final Clr industrial, hospital, school, cemetery, military, apron;
  late final Clr runway;
  late final Clr taxiway, path, bldOutline, casingWarm, motorLow, motorMid;
  late final Clr shieldText, parkText, boundaryBg, waterOutline, stateLine;

  Map<String, Clr>? overrideFor(String id) => overrides[id];
}

/// Repaints a complete Apple-style document into the palette [p]. Only
/// paint *-color values change — schema, layers, sprites, glyph fonts and
/// every minzoom stay exactly as generated (the v3 lesson: the style schema
/// must never be touched).
String _restyleAppleDoc(String baseJson, PremiumPalette p, MapStyle type) {
  Map<String, dynamic> doc;
  try {
    doc = jsonDecode(baseJson) as Map<String, dynamic>;
  } catch (_) {
    return baseJson; // never break the map on our own account
  }
  final r = _AtlasRoles(p);
  final layers = doc['layers'] as List? ?? const [];
  for (final layer in layers) {
    if (layer is! Map<String, dynamic>) continue;
    final paint = layer['paint'];
    if (paint is! Map<String, dynamic>) continue;
    final over = r.overrideFor((layer['id'] ?? '') as String);
    for (final key in paint.keys.toList()) {
      if (!key.toLowerCase().contains('color')) continue;
      paint[key] = _remapApple(paint[key], r, over);
    }
  }
  doc['name'] = 'Navigo Atlas ${type.name}';
  doc['id'] = 'atlas-${type.name}';
  return jsonEncode(doc);
}

dynamic _remapApple(dynamic value, _AtlasRoles r, Map<String, Clr>? over) {
  if (value is String) {
    final c = Clr.parse(value);
    if (c == null) return value;
    final key = '${Clr._h(c.r)}${Clr._h(c.g)}${Clr._h(c.b)}';
    final mapped = over?[key] ?? r.byLiteral[key];
    if (mapped == null) return value; // unknown literal stays Apple-native
    return mapped.withAlpha(c.a).enc();
  }
  if (value is List) return [for (final e in value) _remapApple(e, r, over)];
  return value;
}

// ── v6.5 MEGA-PREMIUM CARTOGRAPHIES: Atlas (light) & Onyx (dark) ──────────
//
// The user was NOT satisfied with v6.4's paint rewrites («я не просил
// сделать премиум темы сменив цвет! … совершенно другие! отрисовка poi,
// тайлы — совершенно другой стиль!»): v6.5 ships TWO complete, from-
// scratch documents in the spirit of Apple Maps (research-verified:
// measured palettes + the MIT reference cartography of
// github.com/dddevid/MapLibre-GL-JS-AppleMaps-Style on the SAME keyless
// OpenFreeMap tiles). Navigo adaptations are baked into the generated
// documents (fonts, building uncap, Bordeaux rule, POI chips) — see
// apple_docs.dart + poi_chips.dart.
//
// RETIRED here: the v6.4 experimental pair (porcelain/obsidian) — pure
// recolors of Liberty that could never be «совершенно другие».

void _recolorLiberty(Map<String, dynamic> doc, PremiumPalette p) {
  final map = _libertyColorMap(p);
  final landLum = (p.land.lum * 255).round();
  Clr fallback(Clr c) =>
      p.dark ? c.darkened(landLum).withAlpha(c.a) : c.withAlpha(c.a);
  final layers = doc['layers'] as List? ?? const [];
  for (final layer in layers) {
    if (layer is! Map<String, dynamic>) continue;
    final paint = layer['paint'];
    if (paint is! Map<String, dynamic>) continue;
    for (final key in paint.keys.toList()) {
      if (!key.toLowerCase().contains('color')) continue;
      paint[key] = _remap(paint[key], map, fallback);
    }
    // v5.3 FIX for the user's «белый фон с пунктирами»: Liberty paints
    // pedestrian plazas and wetlands with FILL-PATTERN sprites
    // (pedestrian_polygon / wetland_bg_11). Sprites are IMAGES — a color
    // remap cannot touch them, so in every dark (and tinted light) theme
    // they stayed blinding white with a dashed texture. Replace the
    // pattern by a solid palette color: the cartography keeps its meaning,
    // the document stays valid, nothing stays white.
    final pattern = paint['fill-pattern'];
    if (pattern is String) {
      final id = ((layer['id'] ?? '') as String).toLowerCase();
      final Clr c;
      if (id.contains('wetland')) {
        c = p.park.mix(p.water, 0.42);
      } else if (id.contains('road_area') || id.contains('pedestrian')) {
        // Plaza: a half-step between road fill and land.
        c = p.road.mix(p.land, p.dark ? 0.42 : 0.30);
      } else {
        c = p.road.mix(p.land, 0.5);
      }
      paint.remove('fill-pattern');
      paint['fill-color'] = c.enc();
      paint['fill-outline-color'] = p.roadCasing.withAlpha(0.55).enc();
      final op = paint['fill-opacity'];
      if (op == null) paint['fill-opacity'] = 1;
    }
  }
}

dynamic _remap(
  dynamic value,
  Map<String, Clr> map,
  Clr Function(Clr) fallback,
) {
  if (value is String) {
    final key = value.trim().toLowerCase().replaceAll(' ', '');
    final parsed = Clr.parse(key);
    if (parsed == null) return value;
    return (map[key] ?? fallback(parsed)).enc();
  }
  if (value is List) return [for (final e in value) _remap(e, map, fallback)];
  return value;
}

/// The complete semantic mapping of Liberty's 43 color literals. Keys are
/// normalized (lowercase, no spaces) exactly like [_remap] normalizes.
Map<String, Clr> _libertyColorMap(PremiumPalette p) {
  final grass = p.park.mix(p.land, 0.30);
  final wood = p.park.mix(p.land, 0.15);
  final pitch = p.park.mix(p.land, 0.45);
  final cemetery = p.park.mix(p.land, 0.52);
  final hospital = p.land.mix(
    p.dark ? const Clr(112, 62, 74) : const Clr(242, 198, 198),
    0.16,
  );
  final school = p.land.mix(
    p.dark ? const Clr(88, 94, 58) : const Clr(233, 235, 196),
    0.16,
  );
  final sandArea = p.land.mix(
    p.dark ? const Clr(88, 75, 46) : const Clr(234, 217, 160),
    0.38,
  );
  final ice = p.dark
      ? p.land.mix(const Clr(216, 230, 234), 0.14)
      : const Clr(226, 237, 237);
  final aeroway = p.land.mix(p.building, 0.5);
  final runway = aeroway.mix(p.building, 0.5);
  final pathLine = p.road.mix(p.roadCasing, 0.35);
  final hwyLow = p.highway.mix(p.highwayCasing, 0.35);
  final bndMinor = p.boundary.mix(p.land, 0.45);
  final parkOutline = p.park.mix(p.label, 0.22);
  final parkOutlineLine = p.park.mix(p.land, 0.4);
  final waterPt = p.waterLabel.mix(p.label, 0.35);
  final transit = p.waterLabel.mix(p.poiLabel, 0.5);
  final labelSoft = p.label.mix(p.poiLabel, 0.4);
  // v5.4: the building outline must CONTRAST with the fill so houses read
  // at a glance: on dark themes lighter than the fill, on light themes
  // darker (the old mix-toward-land made dark-theme outlines disappear).
  final bldOutline = p.dark
      ? p.building.mix(p.label, 0.30)
      : p.building.mix(p.label, 0.26);

  return {
    // Land + path-label halo (same literal in Liberty).
    '#f8f4f0': p.land,
    // Green family.
    '#d8e8c8': p.park,
    'rgba(95,208,100,1)': parkOutline,
    'rgba(228,241,215,1)': parkOutlineLine,
    'hsla(98,61%,72%,0.7)': wood.withAlpha(0.7),
    'rgba(176,213,154,1)': grass,
    '#dee3cd': pitch,
    'hsl(75,37%,81%)': cemetery,
    '#fde': hospital,
    'rgb(236,238,204)': school,
    // Water.
    '#a0c8f0': p.water,
    'rgb(158,189,255)': p.water,
    // Special areas.
    'rgba(247,239,195,1)': sandArea,
    'rgba(224,236,236,1)': ice,
    'rgba(229,228,224,1)': aeroway,
    '#f0ede9': runway,
    'hsla(0,3%,85%,0.84)': p.resolvedResidential.withAlpha(0.84),
    'hsla(35,57%,88%,0.49)': p.resolvedResidential.withAlpha(0.49),
    // Roads: casings.
    '#e9ac77': p.highwayCasing,
    '#cfcdca': p.roadCasing,
    'hsl(36,6%,74%)': p.roadCasing,
    'hsl(35,6%,80%)': p.roadCasing,
    // Roads: fills.
    'hsl(0,0%,100%)': pathLine, // pedestrian paths
    '#fc8': p.highway,
    'hsl(26,87%,62%)': hwyLow, // motorway at low zoom
    '#ffdaa6': p.highway, // tunnel motorway
    '#fff4c6': p.major,
    '#fea': p.major,
    '#fff': p.road,
    // Rails.
    '#bbb': p.rail,
    // Buildings (fill + 3D extrusion + outline interpolate).
    'hsl(35,8%,85%)': p.building,
    'hsl(35,6%,79%)': bldOutline,
    'hsla(35,6%,79%,0.32)': bldOutline.withAlpha(0.32),
    // Boundaries.
    'hsl(0,0%,70%)': bndMinor,
    'hsl(248,1%,41%)': p.boundary,
    // Labels.
    '#74aee9': p.waterLabel,
    '#495e91': waterPt,
    '#666': p.poiLabel,
    '#2e5a80': transit,
    'hsl(30,23%,62%)': p.roadLabel,
    '#333': labelSoft,
    '#000': p.label,
    '#ffffff': p.labelHalo,
    'rgba(255,255,255,0.7)': p.labelHalo.withAlpha(0.7),
  };
}

/// Fast pre-flight probe of a HOSTED style URL (inline JSON docs always
/// succeed — they need no network to parse).
///
/// v5: instead of staring at a boot screen for the full watchdog window on
/// an unstable connection, we detect a dead provider in ≤6 s and start the
/// simplified raster basemap immediately.
Future<bool> probeStyle(
  String styleString, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  if (styleString.startsWith('{')) return true;
  try {
    final res = await http
        .get(Uri.parse(styleString))
        .timeout(timeout, onTimeout: () => http.Response('', 408));
    return res.statusCode == 200 && res.bodyBytes.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Pull the real symbol layer ids out of a hosted style so POI hit-testing
/// follows whatever the provider named them. JSON documents (raster modes)
/// have no vector layers → empty list.
Future<List<String>> discoverPoiLayers(String styleString) async {
  if (styleString.startsWith('{')) return const [];
  try {
    final res = await http
        .get(Uri.parse(styleString))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];
    final doc = jsonDecode(res.body) as Map<String, dynamic>;
    final layers = (doc['layers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    int score(String id) {
      final l = id.toLowerCase();
      if (l.contains('poi') || l.contains('transit')) return 4;
      if (l.contains('airport')) return 3;
      if (l.contains('label')) return 2;
      if (l.contains('name')) return 1;
      return 0;
    }

    final ids = layers
        .where((l) => l['type'] == 'symbol')
        .map<String>((l) => l['id'] as String)
        .toList();
    ids.sort((a, b) => score(b).compareTo(score(a)));
    return ids.take(24).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

// ── Raster-only documents (cannot fail on expressions: there are none) ────
//
// v5.3 SATELLITE OVERHAUL (user report: «на карте по всюду написано нужен
// апи ключ»): CARTO killed its free RASTER tiles — every
// basemaps.cartocdn.com/rastertiles/… request now returns an image stamped
// "API KEY REQUIRED" (HTTP 200, so no error is even visible). The old
// satellite label overlay was such a raster. The hybrid is now built from
// pieces that need NO key anywhere: Esri World Imagery raster + the REAL
// Liberty label layers (vector tiles, sprites and glyphs from OpenFreeMap
// — the same provider as Classic, verified keyless).

/// The satellite document: Esri-only while Liberty is not fetched yet, then
/// hot-swapped into the full hybrid by the widget's style signature.
String? _satelliteHybridDoc;

bool get satelliteReady => _satelliteHybridDoc != null;

/// Builds the satellite hybrid from the shared Liberty document: keeps its
/// ENTIRE symbol layer set (place/POI/road labels, shields, one-way arrows)
/// on top of Esri imagery. Only layers are copied — schema untouched.
Future<void> ensureSatelliteStyle() async {
  if (_satelliteHybridDoc != null) return;
  final raw = await ensureLibertyRaw();
  if (raw == null) return;
  try {
    final liberty = jsonDecode(raw) as Map<String, dynamic>;
    final src = liberty['sources'] as Map<String, dynamic>? ?? const {};
    final omt = src['openmaptiles'];
    if (omt == null) return;
    final symbolLayers = (liberty['layers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((l) => l['type'] == 'symbol')
        .toList();
    if (symbolLayers.isEmpty) return;
    final doc = <String, dynamic>{
      'version': 8,
      'name': 'Navigo Satellite Hybrid',
      // Same sprite + glyphs as Classic — all icons/text render identically.
      'sprite': liberty['sprite'],
      'glyphs': liberty['glyphs'],
      'sources': {'esri': _esriSource(), 'openmaptiles': omt},
      'layers': [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': '#0b0f14'},
        },
        {
          'id': 'esri-imagery',
          'type': 'raster',
          'source': 'esri',
          'paint': {'raster-opacity': 1},
        },
        ...symbolLayers,
      ],
    };
    _satelliteHybridDoc = jsonEncode(doc);
  } catch (_) {
    // Keep the plain Esri document until a later attempt succeeds.
  }
}

Map<String, dynamic> _esriSource() => {
  'type': 'raster',
  'tiles': [
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  ],
  'tileSize': 256,
  'maxzoom': 19,
  'attribution': 'Esri, Maxar, Earthstar Geographics',
};

String _satelliteDoc() => jsonEncode({
  'version': 8,
  'name': 'Navigo Satellite',
  'sources': {'esri': _esriSource()},
  'layers': [
    {
      'id': 'bg',
      'type': 'background',
      'paint': {'background-color': '#0b0f14'},
    },
    {
      'id': 'esri-imagery',
      'type': 'raster',
      'source': 'esri',
      'paint': {'raster-opacity': 1},
    },
  ],
});

String _reliefDoc() => jsonEncode({
  'version': 8,
  'name': 'Navigo Relief',
  'sources': {
    'otm': {
      'type': 'raster',
      'tiles': [
        'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
        'https://b.tile.opentopomap.org/{z}/{x}/{y}.png',
        'https://c.tile.opentopomap.org/{z}/{x}/{y}.png',
      ],
      'tileSize': 256,
      'maxzoom': 17,
      'attribution':
          '© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)',
    },
  },
  'layers': [
    {
      'id': 'bg',
      'type': 'background',
      'paint': {'background-color': '#eef0e9'},
    },
    {
      'id': 'otm-relief',
      'type': 'raster',
      'source': 'otm',
      'paint': {'raster-opacity': 1},
    },
  ],
});

String _fallbackDoc() => jsonEncode({
  'version': 8,
  'name': 'Navigo Simple',
  // v5.3: CARTO raster tiles now answer "API KEY REQUIRED" images (the
  // user's report) — the simplified fallback moves to the classic
  // OpenStreetMap raster tiles (independent provider, no key, honest
  // attribution).
  'sources': {
    'osm': {
      'type': 'raster',
      'tiles': ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      'tileSize': 256,
      'maxzoom': 19,
      'attribution': '© OpenStreetMap contributors',
    },
  },
  'layers': [
    {
      'id': 'bg',
      'type': 'background',
      'paint': {'background-color': '#f4f1ec'},
    },
    {
      'id': 'osm-raster',
      'type': 'raster',
      'source': 'osm',
      'paint': {'raster-opacity': 1},
    },
  ],
});
