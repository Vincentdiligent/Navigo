/// Map engine: owns the MapLibre controller, style lifecycle, sprites,
/// overlay layers (route, pins, selection pulse, user puck) and camera work.
///
/// v4: the base map is always a hosted StylePack (see style_pack.dart) —
/// the engine only manages overlays, hit-testing and the camera. POI
/// hit-testing uses dynamically discovered layer ids when available.
///
/// Built against maplibre_gl 0.27.x APIs: layers use *LayerProperties,
/// style changes flow through the widget's `styleString`, and the selection
/// pulse is data-driven (source properties), not paint mutation.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/app_state.dart';
import 'poi_chips.dart';
import 'sprites.dart';
import 'style_pack.dart';

const String kRouteSrc = 'lux-route';
const String kTraveledSrc = 'lux-traveled';
const String kSelSrc = 'lux-sel';
const String kPinSrc = 'lux-pins';
const String kFavSrc = 'lux-favs';
const String kIncSrc = 'lux-inc';
const String kPuckSrc = 'lux-puck';
const String kTransitSrc = 'lux-transit';
const String kCamSrc = 'lux-cams';
const String kBldSrc = 'lux-bldsel';

/// v5.5 CRITICAL ROOT-CAUSE FIX (the user saw «маршрут не прокладывается»
/// in every release since v5.0):
///
/// MapLibre layer/symbol properties travel through a platform channel that
/// uses StandardMessageCodec — and StandardMessageCodec CANNOT encode a
/// Flutter `Color` object (verified: encodeMessage({'lineColor': Color})
/// throws "Invalid argument: Instance of 'Color'").
///
/// The route line / casing / traveled / selection-circle layers were built
/// with `lineColor: Color(...)` — every addLineLayer/addCircleLayer call
/// threw BEFORE reaching native code, the error was swallowed by the
/// install guard, the route SOURCE existed but NO layer ever rendered it.
/// Pins and favorites kept working because SymbolLayerProperties only held
/// strings — exactly what the user observed (pins fine, route invisible).
///
/// EVERY color below is now a '#rrggbb' STRING (valid MapLibre paint).
String colHex(String rgb) => '#$rgb';

String colorToHex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

String clrHex(Clr c) {
  String p(int v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${p(c.r)}${p(c.g)}${p(c.b)}';
}

/// Last known puck position/kind — survives style reloads (the layer is
/// re-created on every style load, the marker must re-appear instantly).
class _PuckState {
  const _PuckState({
    required this.kind,
    required this.lat,
    required this.lon,
    required this.bearing,
    required this.shown,
  });

  final PuckKind kind;
  final double lat, lon, bearing;
  final bool shown;
}

/// A POI feature picked on the map.
class PickedFeature {
  const PickedFeature(this.name, this.category, this.lat, this.lon);
  final String name;
  final String category; // tile class/subclass
  final double lat, lon;
}

/// v5.9: a BUILDING footprint picked on the map — the user selects which
/// house to look at («чтобы я сам выбрал на карте какие будут»). The ring
/// is [lat, lon] pairs of the outer contour; the centroid anchors the
/// selection pulse and the info card.
class BuildingPick {
  const BuildingPick({
    required this.ring,
    required this.lat,
    this.lon = 0,
    this.heightM,
    this.name,
  });

  final List<List<double>> ring;
  final double lat, lon;
  final double? heightM;
  final String? name;

  double get centroidLat {
    if (ring.isEmpty) return lat;
    var s = 0.0;
    for (final p in ring) {
      s += p[0];
    }
    return s / ring.length;
  }

  double get centroidLon {
    if (ring.isEmpty) return lon;
    var s = 0.0;
    for (final p in ring) {
      s += p[1];
    }
    return s / ring.length;
  }
}

/// v5.7: one colored polyline of a transit itinerary leg.
class TransitLineLeg {
  const TransitLineLeg(this.line, {required this.walk, required this.color});
  final List<List<double>> line; // [lat, lon]
  final bool walk; // walking legs render dashed + neutral
  final String color; // '#rrggbb'
}

class MapEngine {
  MapLibreMapController? _c;
  bool _styleReady = false;
  Timer? _pulse;
  double _pulsePhase = 0;
  String _cachedSig = '';
  String _cachedDoc = '';

  /// v5.4: true when the current style is the HOSTED Liberty URL (the only
  /// major style whose flat building layer keeps the maxzoom=14 cap —
  /// inline recolors are patched in the document itself).
  bool _hostedLiberty = false;

  /// Hit-test layers of the currently loaded style.
  List<String> _poiLayers = const [];

  /// Whether the current style is vector (POI tap + 3D toggle meaningful).
  bool _vector = false;

  /// v6.1: attach is RE-ENTRANT — the wake rebuild (home_screen) creates a
  /// fresh native map view and attaches its controller. The new style has
  /// nothing installed yet, so every cached “ready” flag must reset;
  /// overlays re-install in onStyleLoaded as after any style switch.
  void attach(MapLibreMapController c) {
    _c = c;
    _styleReady = false;
  }

  bool get ready => _c != null && _styleReady;

  /// v5.4: the live camera (trackCameraPosition is enabled on the widget).
  CameraPosition? get cameraPosition => _c?.cameraPosition;

  bool get vectorStyle => _vector;

  /// The style string for the current settings (URL or inline JSON doc).
  /// The widget passes this as `styleString`; when the signature changes
  /// the widget reloads the style natively and [onStyleLoaded] re-installs
  /// overlays. v5.2: the signature tracks pack readiness so a premium
  /// recolor that finishes generating AFTER the map booted hot-swaps in.
  /// v6.7: the DRAWN theme is `state.renderedStyle` — AUTO-NIGHT's shade
  /// changes what the basemap looks like without touching the saved pick.
  String styleJson(AppState state, {bool fallback = false}) {
    // v6.6: the premium render family is part of the signature — switching
    // «Классика ↔ Премиум Atlas» swaps the document without a restart.
    final sig =
        '${state.renderedStyle.name}|${state.premiumRender ? 1 : 0}|$fallback|${packReadyFor(state.renderedStyle, state.premiumRender)}'
            .replaceAll('true', '1')
            .replaceAll('false', '0');
    if (sig == _cachedSig && _cachedDoc.isNotEmpty) return _cachedDoc;
    _cachedSig = sig;
    final pack = fallback
        ? fallbackPack
        : packForFamily(state.renderedStyle, state.premiumRender);
    _poiLayers = pack.poiLayerIds;
    _vector = pack.vector;
    _hostedLiberty = pack.styleString == kStyleLiberty;
    _cachedDoc = pack.styleString;
    return _cachedDoc;
  }

  /// Discover the hosted style's real symbol layer ids (async, best
  /// effort). Call right after the map is created; pickPoi keeps working
  /// with the built-in list if the fetch fails.
  Future<void> prepareLayers(AppState state, {required bool fallback}) async {
    final pack = fallback
        ? fallbackPack
        : packForFamily(state.renderedStyle, state.premiumRender);
    _vector = pack.vector;
    final dyn = await discoverPoiLayers(pack.styleString);
    if (dyn.isNotEmpty) _poiLayers = dyn;
  }

  /// Pre-flight probe of the primary hosted style (v5): on a dead/slow
  /// network the UI learns within ~6 s that the basemap must start in
  /// simplified raster mode instead of staring at the boot screen.
  Future<bool> probePrimary(AppState state) => probeStyle(
      packForFamily(state.renderedStyle, state.premiumRender).styleString);

  /// Called by the widget when the style finished (re)loading.
  ///
  /// CRITICAL (v5): this must NEVER throw. Sprites/overlays/3D are
  /// best-effort decorations; a failure here must not prevent the app from
  /// recognizing that the MAP ITSELF has loaded.
  Future<void> onStyleLoaded(AppState state) async {
    final c = _c;
    if (c == null) return;
    _styleReady = true;
    try {
      await registerSprites(
        (name, bytes) => c.addImage(name, bytes),
        state.effectiveTheme.primary,
      );
    } catch (_) {
      // Sprite registration is optional (addImage of an existing name,
      // GPU-less early frames, …) — the basemap does not depend on it.
    }
    try {
      // v6.5: the Apple-Maps-like cartographies draw POIs as COLORED
      // CHIPS (a-food, a-cafe, …) — the icons are canvas-drawn and
      // registered here, right after the style lands. The document's
      // symbol layers may render for a few frames without them (text
      // still shows) — the v6.5 fade-in masks that moment too.
      // v6.6: EVERY theme of the premium render family rides the same
      // Apple documents (repainted) — chips register for all of them.
      // v6.6.1: and they are painted FROM THAT THEME'S PALETTE (chip
      // body, ring, glyph contrast), keyed per theme so the bitmaps are
      // cached and a theme switch stays instant.
      final look = atlasLookFor(state.renderedStyle, state.premiumRender);
      if (look != null) {
        await registerPoiChips(
          (n, b) => c.addImage(n, b),
          look.palette.dark,
          deco: look.deco,
          cacheId: state.renderedStyle.name,
          tag: chipTagFor(state.renderedStyle),
        );
      }
    } catch (_) {
      // Chip registration is optional — POIs degrade to labels only.
    }
    try {
      await _installOverlays(state);
    } catch (_) {}
    try {
      // v5.4: hosted Classic keeps Liberty's maxzoom=14 cap on the flat
      // building layer — patch it with an uncapped 2D fill so «дома не
      // видны при зуме» never happens on the default theme either.
      if (_hostedLiberty) await _ensureFlatBuildings();
    } catch (_) {}
    try {
      // v5.9: the persisted buildings mode (Обычные / 3D / Выкл).
      await applyBuildingsMode(state.buildingsMode);
    } catch (_) {}
  }

  /// v5.4: adds an uncapped flat building fill (same source, same colors
  /// as Liberty's own) BELOW the 3D extrusion. The 3D toggle then only
  /// controls the extrusion — footprints stay visible at every zoom.
  Future<void> _ensureFlatBuildings() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    const props = FillLayerProperties(
      fillColor: '#e3ded3',
      fillOutlineColor: '#cdc6b7',
      fillOpacity: 1,
    );
    try {
      await c.addFillLayer(
        'openmaptiles',
        'lux-building-flat',
        props,
        sourceLayer: 'building',
        minzoom: 13,
        belowLayerId: 'building-3d',
      );
    } catch (_) {
      // building-3d missing or already added — retry without the anchor.
      try {
        await c.addFillLayer(
          'openmaptiles',
          'lux-building-flat',
          props,
          sourceLayer: 'building',
          minzoom: 13,
        );
      } catch (_) {}
    }
  }

  // ── GeoJSON helpers ───────────────────────────────────────────────────
  static Map<String, dynamic> feature(
    String type,
    List<dynamic> coordinates, [
    Map<String, dynamic>? props,
  ]) =>
      {
        'type': 'Feature',
        'geometry': {'type': type, 'coordinates': coordinates},
        'properties': props ?? const {},
      };

  /// v5 CRITICAL FIX: the app works with [lat, lon] pairs everywhere
  /// (route service, favorites, pins), but GeoJSON mandates [lon, lat].
  /// Feeding [lat, lon] straight into a LineString produced transposed
  /// coordinates (lat≈49° as longitude is invalid) — MapLibre silently
  /// drew NOTHING. That was exactly the "маршрут не появляется" bug.
  static List<double> _xy(List<double> p) => [p[1], p[0]];

  static List<List<double>> _line(List<List<double>> latlng) =>
      latlng.map(_xy).toList();

  static Map<String, dynamic> _emptyLine() =>
      _fc([feature('LineString', <double>[])]);
  static Map<String, dynamic> _emptyPoint() =>
      _fc([feature('Point', <double>[], {'r': 12, 'o': 0.3})]);
  static Map<String, dynamic> _emptyPolygon() =>
      // A degenerate-but-VALID polygon (empty `coordinates: []` is rejected
      // by the native GeoJSON converter).
      _fc([
        feature('Polygon', <dynamic>[
          <List<double>>[
            <double>[0, 0],
            <double>[0.0001, 0],
            <double>[0, 0.0001],
            <double>[0, 0],
          ],
        ]),
      ]);
  static Map<String, dynamic> _emptyFeatures() => _fc(const []);

  static Map<String, dynamic> _fc(List<Map<String, dynamic>> features) => {
        'type': 'FeatureCollection',
        'features': features,
      };

  // ── Overlay layers ─────────────────────────────────────────────────────
  /// Idempotent install (v5): a repeated onStyleLoaded (style reload,
  /// watchdog fallback switch) used to throw "source already exists" and
  /// break the whole load chain. Remove stale ids first, ignore errors.
  Future<void> _installOverlays(AppState state) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final t = state.effectiveTheme;
    // v6.6.1: when the basemap is an Atlas document, the route line is
    // painted from THAT theme's palette — a signal color that keeps its
    // distance from the theme's own road colors, with a casing carved out of
    // the basemap. On host-drawn Classic/imagery the app tokens still rule.
    final deco = atlasLookFor(state.renderedStyle, state.premiumRender)?.deco;
    final routeLineHex = deco != null ? clrHex(deco.route) : colHex(t.map.route);
    final routeCasingHex =
        deco != null ? clrHex(deco.routeCasing) : colHex(t.map.routeCasing);
    final traveledHex =
        deco != null ? clrHex(deco.routeTraveled) : colHex(t.map.traveled);

    for (final id in const [
      'ov-route-casing', 'ov-route-line', 'ov-route-traveled',
      'ov-sel-halo', 'ov-sel-core', 'ov-pins', 'ov-favs',
      'ov-incidents', 'ov-puck',
      'ov-transit-walk', 'ov-transit-ride', 'ov-cams',
      'ov-bld-sel',
    ]) {
      try {
        await c.removeLayer(id);
      } catch (_) {}
    }
    for (final src in const [
      kRouteSrc, kTraveledSrc, kSelSrc, kPinSrc, kFavSrc, kIncSrc, kPuckSrc,
      kTransitSrc, kCamSrc, kBldSrc,
    ]) {
      try {
        await c.removeSource(src);
      } catch (_) {}
    }

    /// v5 hardening: EVERY install step is isolated. If any single source or
    /// layer fails (race with a style switch, transient native error), the
    /// remaining overlays still get installed — one broken piece must not
    /// take down route + pins + user puck + favorites with it.
    /// v5.5: failures are logged (debugPrint) so a future device report can
    /// be diagnosed from logcat instead of staying invisible.
    Future<void> add(String what, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        debugPrint('[Navigo] overlay install failed: $what — $e');
      }
    }

    await add('src route', () => c.addGeoJsonSource(kRouteSrc, _emptyLine()));
    await add('src traveled', () => c.addGeoJsonSource(kTraveledSrc, _emptyLine()));
    await add('src sel', () => c.addGeoJsonSource(kSelSrc, _emptyPoint()));
    await add('src pins', () => c.addGeoJsonSource(kPinSrc, _emptyFeatures()));
    await add('src favs', () => c.addGeoJsonSource(kFavSrc, _emptyFeatures()));
    await add('src incidents', () => c.addGeoJsonSource(kIncSrc, _emptyFeatures()));
    await add('src puck', () => c.addGeoJsonSource(kPuckSrc, _emptyFeatures()));
    await add('src transit', () => c.addGeoJsonSource(kTransitSrc, _emptyFeatures()));
    await add('src cams', () => c.addGeoJsonSource(kCamSrc, _emptyFeatures()));
    await add('src bldsel', () => c.addGeoJsonSource(kBldSrc, _emptyPolygon()));

    await add(
      'layer route-casing',
      () => c.addLineLayer(
        kRouteSrc,
        'ov-route-casing',
        LineLayerProperties(
          // v5.5: STRING colors — Color objects crash the platform codec.
          lineColor: routeCasingHex,
          lineWidth: 11,
          lineOpacity: 0.9,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      ),
    );
    await add(
      'layer route-line',
      () => c.addLineLayer(
        kRouteSrc,
        'ov-route-line',
        LineLayerProperties(
          lineColor: routeLineHex,
          lineWidth: 6.5,
          lineOpacity: 1,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      ),
    );
    await add(
      'layer route-traveled',
      () => c.addLineLayer(
        kTraveledSrc,
        'ov-route-traveled',
        LineLayerProperties(
          lineColor: traveledHex,
          lineWidth: 5.5,
          lineOpacity: 0.9,
          lineJoin: 'round',
          lineCap: 'round',
        ),
      ),
    );

    // v5.9: the SELECTED BUILDING fill — the house the user tapped lights
    // up in the theme accent. Lives directly under the route casing so the
    // line, pins and labels always stay on top of the highlight.
    await add(
      'layer bld-sel',
      () => c.addFillLayer(
        kBldSrc,
        'ov-bld-sel',
        FillLayerProperties(
          fillColor: colorToHex(t.primary),
          fillOpacity: 0.32,
          fillOutlineColor: colorToHex(t.primary),
        ),
        belowLayerId: 'ov-route-casing',
      ),
    );

    await add(
      'layer sel-halo',
      () => c.addCircleLayer(
        kSelSrc,
        'ov-sel-halo',
        CircleLayerProperties(
          circleRadius: ['get', 'r'],
          circleColor: colorToHex(t.primary),
          circleOpacity: ['get', 'o'],
          circleStrokeWidth: 0,
        ),
      ),
    );
    await add(
      'layer sel-core',
      () => c.addCircleLayer(
        kSelSrc,
        'ov-sel-core',
        CircleLayerProperties(
          circleRadius: 7,
          circleColor: '#ffffff',
          circleOpacity: 0.95,
          circleStrokeWidth: 3,
          circleStrokeColor: colorToHex(t.primary),
        ),
      ),
    );
    // v5.5: roadworks / closures along the route (OpenStreetMap data) —
    // amber warning dots that survive every theme.
    await add(
      'layer incidents',
      () => c.addCircleLayer(
        kIncSrc,
        'ov-incidents',
        const CircleLayerProperties(
          circleRadius: 6.5,
          circleColor: '#FFB300',
          circleOpacity: 0.95,
          circleStrokeWidth: 2.4,
          circleStrokeColor: '#FFFFFF',
        ),
      ),
    );

    await add(
      'layer pins',
      () => c.addSymbolLayer(
        kPinSrc,
        'ov-pins',
        const SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 1,
          // v5.7: the teardrop TIP must sit on the geographic point —
          // the default 'center' anchor made pins float mid-air.
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
        ),
        filter: ['has', 'icon'],
      ),
    );
    await add(
      'layer favs',
      () => c.addSymbolLayer(
        kFavSrc,
        'ov-favs',
        const SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 1,
          // v5.7: tip-on-point anchors for the Home/Work/Favorites pins.
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          symbolSortKey: ['get', 'rank'],
        ),
      ),
    );
    // v5.8: fixed speed cameras along the route (OSM) — red badges that
    // sit right above the incidents layer and below the pins.
    await add(
      'layer cams',
      () => c.addSymbolLayer(
        kCamSrc,
        'ov-cams',
        const SymbolLayerProperties(
          iconImage: 'lux-cam',
          iconSize: 1,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          symbolSortKey: 2,
        ),
      ),
    );
    // v5.6: THE MOVING MARKER (стрелка / машина / велосипед / человек).
    // Rotates with the course bearing, lies flat on the map plane so it
    // behaves exactly like a real navigator arrow during turn-by-turn.
    await add(
      'layer puck',
      () => c.addSymbolLayer(
        kPuckSrc,
        'ov-puck',
        const SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 1,
          iconRotate: ['get', 'bearing'],
          iconRotationAlignment: 'map',
          iconPitchAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      ),
    );
    // Re-apply the last puck state on the freshly (re)loaded style.
    await add('puck reapply', () => _applyPuck());
    // v6.7: same for the saved places — the fav source was just recreated
    // empty, and the UI won't push it again unless the places changed.
    await add('favs reapply', _pushFavorites);

    // ── v5.7: TRANSIT ROUTE (общественный транспорт) ────────────────────
    // One GeoJSON source, TWO layers: walking legs are dashed neutral
    // lines, transit legs are thick data-driven colored lines (the GTFS
    // line color when the agency provides one). Filtered on the feature
    // properties; both re-created idempotently on style reloads.
    await add(
      'layer transit-walk',
      () => c.addLineLayer(
        kTransitSrc,
        'ov-transit-walk',
        LineLayerProperties(
          lineColor: colHex(t.map.traveled),
          lineWidth: 4.5,
          lineOpacity: 0.95,
          lineDasharray: [1.6, 1.6],
          lineJoin: 'round',
          lineCap: 'round',
        ),
        filter: ['==', ['get', 'kind'], 'walk'],
        belowLayerId: 'ov-pins',
      ),
    );
    await add(
      'layer transit-ride',
      () => c.addLineLayer(
        kTransitSrc,
        'ov-transit-ride',
        LineLayerProperties(
          // GTFS line color per feature, premium casing via the theme.
          lineColor: ['get', 'color'],
          lineWidth: 6.5,
          lineOpacity: 1,
          lineJoin: 'round',
          lineCap: 'round',
        ),
        filter: ['==', ['get', 'kind'], 'ride'],
        belowLayerId: 'ov-pins',
      ),
    );
  }

  // ── v5.6: the moving marker (стрелка / машина / велосипед / человек) ───
  _PuckState _puck = const _PuckState(kind: PuckKind.arrow, lat: 0, lon: 0, bearing: 0, shown: false);

  /// Shows / hides the custom moving marker. [shown=false] clears the layer
  /// (the native blue dot takes over again).
  Future<void> setPuck({
    required bool shown,
    PuckKind kind = PuckKind.arrow,
    required double lat,
    required double lon,
    required double bearing,
  }) async {
    _puck = _PuckState(kind: kind, lat: lat, lon: lon, bearing: bearing, shown: shown);
    final c = _c;
    if (c == null || !_styleReady) return;
    try {
      await _applyPuck();
    } catch (_) {}
  }

  Future<void> _applyPuck() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final p = _puck;
    final data = (p.shown && p.kind != PuckKind.dot)
        ? _fc([
            feature('Point', [p.lon, p.lat], {
              'icon': 'lux-puck-${p.kind.name}',
              'bearing': p.bearing,
            }),
          ])
        : _emptyFeatures();
    try {
      await c.setGeoJsonSource(kPuckSrc, data);
    } catch (_) {
      try {
        await c.addGeoJsonSource(kPuckSrc, data);
      } catch (_) {}
    }
  }

  // ── Public overlays API ───────────────────────────────────────────────

  /// v5.7: draws a transit itinerary — every leg in ITS color (GTFS line
  /// colors), walking legs dashed. null clears the layer.
  Future<void> drawTransit(List<TransitLineLeg>? legs) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final data = (legs == null || legs.isEmpty)
        ? _emptyFeatures()
        : _fc([
            for (final leg in legs)
              if (leg.line.length >= 2)
                feature(
                  'LineString',
                  _line(leg.line),
                  {
                    'kind': leg.walk ? 'walk' : 'ride',
                    'color': leg.color,
                  },
                ),
          ]);
    try {
      await c.setGeoJsonSource(kTransitSrc, data);
    } catch (_) {
      try {
        await c.addGeoJsonSource(kTransitSrc, data);
      } catch (_) {}
    }
  }

  Future<void> drawRoute(List<List<double>>? line) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final data = (line == null || line.length < 2)
        ? _emptyLine()
        : _fc([feature('LineString', _line(line))]);
    try {
      await c.setGeoJsonSource(kRouteSrc, data);
    } catch (_) {
      // v5.5 hardening: the source may be missing right after a style
      // reload raced the install — recreate it with the data directly.
      try {
        await c.addGeoJsonSource(kRouteSrc, data);
      } catch (_) {}
    }
  }

  Future<void> drawTraveled(List<List<double>> line) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(
      kTraveledSrc,
      line.length < 2
          ? _emptyLine()
          : _fc([feature('LineString', _line(line))]),
    );
  }

  Future<void> setPins({
    List<List<double>>? points,
    List<String>? icons,
  }) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    if (points == null || points.isEmpty) {
      await c.setGeoJsonSource(kPinSrc, _emptyFeatures());
      return;
    }
    final feats = <Map<String, dynamic>>[];
    for (var i = 0; i < points.length; i++) {
      feats.add(
        feature('Point', _xy(points[i]), {'icon': icons?[i] ?? 'lux-pin-drop'}),
      );
    }
    await c.setGeoJsonSource(kPinSrc, _fc(feats));
  }

  /// The last favorites push, kept so a style reload can replay it.
  /// Null until the UI pushes the saved places for the first time.
  List<List<double>>? _favPoints;
  List<String>? _favIcons;

  /// Saved places as permanent map icons: home (green house), work (red
  /// briefcase) and favorites (amber star). rank: home/work above favs.
  ///
  /// v6.7: the push is CACHED and replayed by [_installOverlays], exactly
  /// like the puck. `_installOverlays` re-creates `kFavSrc` EMPTY on every
  /// style reload, and the caller's signature check then skipped the
  /// re-push — which is how Дом/Работа vanished after any theme switch and
  /// only came back after an app restart.
  Future<void> setFavorites({
    List<List<double>>? points,
    List<String>? icons,
  }) async {
    _favPoints = points ?? const [];
    _favIcons = icons;
    await _pushFavorites();
  }

  Future<void> _pushFavorites() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final points = _favPoints;
    if (points == null) return;
    final icons = _favIcons;
    if (points.isEmpty) {
      await c.setGeoJsonSource(kFavSrc, _emptyFeatures());
      return;
    }
    final feats = <Map<String, dynamic>>[];
    for (var i = 0; i < points.length; i++) {
      final icon = icons?[i] ?? 'lux-fav';
      feats.add(
        feature(
          'Point',
          _xy(points[i]),
          {
            'icon': icon,
            'rank': (icon == 'lux-home' || icon == 'lux-work') ? 10 : 5,
          },
        ),
      );
    }
    await c.setGeoJsonSource(kFavSrc, _fc(feats));
  }

  Future<void> showSelection(double lat, double lon) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    _pulsePhase = 0;
    _selPoint = [lon, lat];
    await c.setGeoJsonSource(
      kSelSrc,
      _fc([feature('Point', _selPoint, {'r': 12, 'o': 0.3})]),
    );
    _startPulse();
  }

  Future<void> clearSelection() async {
    _stopPulse();
    final c = _c;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(kSelSrc, _emptyPoint());
  }

  void _startPulse() {
    _pulse?.cancel();
    _pulse = Timer.periodic(const Duration(milliseconds: 48), (t) async {
      final c = _c;
      if (c == null || !_styleReady) return;
      _pulsePhase += 0.048;
      final phase = _pulsePhase % 1;
      final r = 11 + phase * 13;
      final o = 0.34 * (1 - phase) + 0.04;
      try {
        await c.setGeoJsonSource(
          kSelSrc,
          _fc([feature('Point', _selPoint, {'r': r, 'o': o})]),
        );
      } catch (_) {}
    });
  }

  List<double> _selPoint = const [];

  void _stopPulse() {
    _pulse?.cancel();
    _pulse = null;
  }

  /// 3D buildings: v5.5 — the user reported «отключаю 3d здания они не
  /// отключаются на карте». Two causes, both fixed here:
  ///   1. the v5.4 flat-building overlay (`lux-building-flat`) and the
  ///      uncapped `building` footprint layer kept painting houses after
  ///      the extrusion was hidden;
  ///   2. nothing re-applied the toggle on the live map (it only landed on
  ///      the next style reload) — the HomeScreen now calls this on every
  ///      state change.
  /// All building-carrying layers are switched together; satellite/relief
  /// styles simply no-op (per-layer try/catch).
  /// v5.9: superseded by [applyBuildingsMode] — the boolean wrapper is gone
  /// and the mode itself (Обычные / 3D / Выкл) is the single source of truth.
  Future<void> applyBuildingsMode(BuildingsMode mode) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final extrusion = mode == BuildingsMode.threeD;
    final flat = mode != BuildingsMode.off;
    try {
      await c.setLayerVisibility('building-3d', extrusion);
    } catch (_) {}
    try {
      await c.setLayerVisibility('lux-building-flat', flat);
    } catch (_) {}
    try {
      await c.setLayerVisibility('building', flat);
    } catch (_) {}
  }

  /// v5.5: roadworks / closures along the active route (amber dots).
  Future<void> setIncidents(List<List<double>> points) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final data = points.isEmpty
        ? _emptyFeatures()
        : _fc([
            for (final p in points) feature('Point', _xy(p)),
          ]);
    try {
      await c.setGeoJsonSource(kIncSrc, data);
    } catch (_) {
      try {
        await c.addGeoJsonSource(kIncSrc, data);
      } catch (_) {}
    }
  }

  /// v5.8: fixed speed cameras found around the route (OSM) — drawn as red
  /// badges. The symbol layer survives style reloads via [restoreCams].
  List<List<double>> _lastCams = const [];

  Future<void> setCameras(List<List<double>> points) async {
    _lastCams = points;
    final c = _c;
    if (c == null || !_styleReady) return;
    final data = points.isEmpty
        ? _emptyFeatures()
        : _fc([
            for (final p in points) feature('Point', _xy(p)),
          ]);
    try {
      await c.setGeoJsonSource(kCamSrc, data);
    } catch (_) {
      try {
        await c.addGeoJsonSource(kCamSrc, data);
      } catch (_) {}
    }
  }

  /// Re-apply after a style reload.
  Future<void> restoreCams() => setCameras(_lastCams);

  // ── Hit testing ───────────────────────────────────────────────────────
  Future<PickedFeature?> pickPoi(
    Offset screenPoint,
    double lat,
    double lon,
  ) async {
    final c = _c;
    if (c == null || !_styleReady || !_vector || _poiLayers.isEmpty) {
      return null;
    }
    try {
      final feats = await c.queryRenderedFeatures(
        math.Point<double>(screenPoint.dx, screenPoint.dy),
        _poiLayers,
        null,
      );
      if (feats.isEmpty) return null;
      // Prefer features that actually carry a human-readable name.
      dynamic best = feats.first;
      var bestName = '';
      for (final f in feats) {
        final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
        final n = (props['name'] ?? props['name:ru'] ?? props['name:latin'] ?? '')
            as String;
        if (n.trim().isNotEmpty) {
          best = f;
          bestName = n;
          break;
        }
      }
      if (bestName.isEmpty) return null;
      return _toPicked(best, lat, lon);
    } catch (_) {
      return null;
    }
  }

  PickedFeature _toPicked(dynamic f, double lat, double lon) {
    final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final geo = f['geometry'] as Map?;
    final coords = geo?['coordinates'] as List?;
    final name = (props['name'] ?? props['name:ru'] ?? props['name:latin'] ?? '')
        as String;
    final cls = (props['subclass'] ?? props['class'] ?? '') as String;
    return PickedFeature(
      name.isEmpty ? cls : name,
      cls,
      (coords != null && coords.length >= 2)
          ? (coords[1] as num).toDouble()
          : lat,
      (coords != null && coords.length >= 2)
          ? (coords[0] as num).toDouble()
          : lon,
    );
  }

  // ── v5.9: BUILDING SELECTION («я сам выбрал на карте какие будут») ─────
  /// The flat footprints the user can tap. Works on every vector theme:
  /// hosted Liberty exposes them via our `lux-building-flat` overlay, the
  /// premium recolors via the uncapped `building` layer. The extrusion is
  /// queried too so 3D-mode taps still resolve.
  static const List<String> _hostedBuildingLayers = [
    'lux-building-flat',
    'building-3d',
  ];
  static const List<String> _inlineBuildingLayers = [
    'building',
    'building-3d',
  ];

  /// Hit-tests the building layers at [screenPoint]; returns the footprint
  /// ring ([lat, lon] pairs), its centroid and whatever metadata the tiles
  /// carry (render height / name). null → no building under the finger.
  Future<BuildingPick?> pickBuilding(
    Offset screenPoint,
    double lat,
    double lon,
  ) async {
    final c = _c;
    if (c == null || !_styleReady || !_vector) return null;
    final layers = _hostedLiberty ? _hostedBuildingLayers : _inlineBuildingLayers;
    try {
      final feats = await c.queryRenderedFeatures(
        math.Point<double>(screenPoint.dx, screenPoint.dy),
        layers,
        null,
      );
      for (final f in feats) {
        final geo = f['geometry'] as Map?;
        if (geo == null) continue;
        final ring = _outerRing(geo);
        if (ring.length < 3) continue;
        final props =
            (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
        final height = (props['render_height'] as num?)?.toDouble();
        final name = (props['name'] ?? '') as String;
        return BuildingPick(
          ring: ring,
          lat: lat,
          lon: lon,
          heightM: (height != null && height > 1) ? height : null,
          name: name.trim().isEmpty ? null : name.trim(),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the outer ring of a Polygon/MultiPolygon returned by
  /// queryRenderedFeatures and converts it to [lat, lon] pairs.
  static List<List<double>> _outerRing(Map geo) {
    final type = geo['type'] as String? ?? '';
    final coords = geo['coordinates'] as List?;
    if (coords == null || coords.isEmpty) return const [];
    dynamic polygon = coords;
    if (type == 'MultiPolygon') {
      polygon = coords.first;
    }
    if (polygon is! List || polygon.isEmpty) return const [];
    final ring0 = polygon.first;
    if (ring0 is! List) return const [];
    final out = <List<double>>[];
    for (final p in ring0) {
      if (p is List && p.length >= 2) {
        out.add([(p[1] as num).toDouble(), (p[0] as num).toDouble()]);
      }
    }
    return out;
  }

  /// Lights the picked footprint up in the theme accent (fill + outline).
  Future<void> highlightBuilding(List<List<double>> ring) async {
    final c = _c;
    if (c == null || !_styleReady) return;
    final data = _fc([
      feature(
        'Polygon',
        [ring.map(_xy).toList()],
        const {},
      ),
    ]);
    try {
      await c.setGeoJsonSource(kBldSrc, data);
    } catch (_) {
      try {
        await c.addGeoJsonSource(kBldSrc, data);
      } catch (_) {}
    }
  }

  /// Clears the building highlight.
  Future<void> clearBuildingHighlight() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    try {
      await c.setGeoJsonSource(kBldSrc, _emptyPolygon());
    } catch (_) {}
  }

  // ── Camera ────────────────────────────────────────────────────────────
  Future<void> fitLine(
    List<List<double>> line, {
    double top = 96,
    double bottom = 220,
    double side = 48,
  }) async {
    final c = _c;
    if (c == null || line.length < 2) return;
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in line) {
      minLat = minLat < p[0] ? minLat : p[0];
      maxLat = maxLat > p[0] ? maxLat : p[0];
      minLon = minLon < p[1] ? minLon : p[1];
      maxLon = maxLon > p[1] ? maxLon : p[1];
    }
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        left: side,
        right: side,
        top: top,
        bottom: bottom,
      ),
      duration: const Duration(milliseconds: 850),
    );
  }

  Future<void> zoomTo(double zoom, {Duration duration = const Duration(milliseconds: 600)}) async {
    final c = _c;
    if (c == null) return;
    try {
      final pos = c.cameraPosition;
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: pos!.target, zoom: zoom),
        ),
        duration: duration,
      );
    } catch (_) {}
  }

  Future<void> moveTo(LatLng target, {double? zoom, Duration duration = const Duration(milliseconds: 700)}) async {
    final c = _c;
    if (c == null) return;
    final cur = c.cameraPosition;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom ?? cur?.zoom ?? 14,
          bearing: cur?.bearing ?? 0,
          tilt: cur?.tilt ?? 0,
        ),
      ),
      duration: duration,
    );
  }

  Future<void> navFollow(double lat, double lon, double bearing) async {
    final c = _c;
    if (c == null) return;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lon),
          zoom: 17.2,
          bearing: bearing,
          tilt: 38,
        ),
      ),
      duration: const Duration(milliseconds: 450),
    );
  }

  /// Rotate the camera back to north-up (custom compass button).
  Future<void> resetNorth() async {
    final c = _c;
    if (c == null) return;
    final pos = c.cameraPosition;
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: pos?.target ?? LatLng(48.8566, 2.3522),
          zoom: pos?.zoom ?? 14,
          bearing: 0,
          tilt: pos?.tilt ?? 0,
        ),
      ),
      duration: const Duration(milliseconds: 350),
    );
  }

  Future<void> disposeEngine() async {
    _pulse?.cancel();
    _c = null;
  }
}
