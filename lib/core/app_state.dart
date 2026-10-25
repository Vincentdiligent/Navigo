/// App state: persisted settings + live navigation state (ChangeNotifier).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../route/speed_cameras.dart';
import '../route/transit_model.dart';
import 'lux_theme.dart';
import 'strings.dart';

/// The ONE version the UI shows. It used to be a literal in the About block,
/// where it froze at 5.6.0 while pubspec had long moved on. Keep it in step
/// with `version:` in pubspec.yaml.
const String kAppVersion = '6.9.0';

/// Transport profile for routing. v5.7 adds [transit] — public transport
/// (bus / metro / RER / tram) via the keyless Transitous router.
enum TravelMode { car, bike, foot, transit }

extension TravelModeX on TravelMode {
  String get osrmProfile => switch (this) {
    TravelMode.car => 'car',
    TravelMode.bike => 'bike',
    TravelMode.foot => 'foot',
    // OSRM is never asked for transit — the guard lives in the caller.
    TravelMode.transit => 'foot',
  };

  String get key => name;
}

/// v5.5: what the user optimises for when several route variants exist.
enum RoutePref { fast, short }

/// v5.6: WHAT MOVES on the map while navigating — the user asked for a
/// settings choice («сделай в настройках выбор кто будет двигаться стрелка
/// машина … после запуска маршрута только точка местоположения она не
/// меняется на стрелку или же машину»). [auto] derives the marker from the
/// travel profile: авто → стрелка, велосипед → велосипед, пешком → человек
/// («для велосипеда пусть будет велосипед для пешехода пусть будет
/// человечек»). [dot] keeps the classic round location dot.
enum PuckPref { auto, arrow, car, dot }

/// v5.9: HOW BUILDINGS RENDER — the user asked for flat footprints back
/// («Добавь здания не 3d а обычные чтобы я сам выбрал на карте какие
/// будут!») plus the freedom to pick the mode himself:
///   [flat]   quiet 2D footprints — the new default;
///   [threeD] the classic extruded skyline;
///   [off]    nothing — satellite-clean ground.
/// In EVERY flat/3D mode the footprints stay tappable (выбор здания тапом).
enum BuildingsMode { flat, threeD, off }

/// The RESOLVED marker kind actually drawn on the map.
enum PuckKind { arrow, car, bike, person, dot }

PuckKind resolvePuck(PuckPref pref, TravelMode mode) => switch (pref) {
  PuckPref.arrow => PuckKind.arrow,
  PuckPref.car => PuckKind.car,
  PuckPref.dot => PuckKind.dot,
  PuckPref.auto => switch (mode) {
    TravelMode.car => PuckKind.arrow,
    TravelMode.bike => PuckKind.bike,
    TravelMode.foot => PuckKind.person,
    // Transit rides start and end with a walk — the walker reads best.
    TravelMode.transit => PuckKind.person,
  },
};

/// BASE MAP STYLE: the THEMES the user asked for. Graphite, Noir and
/// Forest are COLORS OF THE MAP ITSELF (premium hosted cartography), not app
/// skins. The app itself has exactly two looks: light and dark.
///
/// v5.2: TEN premium recolors of the Classic (Liberty) document — 5 dark +
/// 5 light — appended AFTER the v5.1 values so saved `lux.mapStyle` indices
/// keep meaning exactly what they meant (enum order is a persisted format).
enum MapStyle {
  classic,
  graphite,
  noir,
  forest,
  satellite,
  relief,
  // v5.2 premium dark recolors of Classic.
  midnight,
  amethyst,
  emerald,
  abyss,
  espresso,
  // v5.2 premium light recolors of Classic.
  pearl,
  sand,
  arctic,
  rose,
  mint,
  // v6.3: the user's style bake-off («все стили рядом сделаем») — hosted
  // keyless OSM Bright (OpenFreeMap, same infra as Classic). Appended at
  // the end so saved lux.mapStyle indices keep their meaning.
  bright,
  // v6.5 MEGA-PREMIUM CARTOGRAPHIES («сделай две именно совершенно другие!
  // отрисовка poi, тайлы — совершенно другой стиль!»): Atlas (light) and
  // Onyx (dark) — complete from-scratch documents in the spirit of Apple
  // Maps (github.com/dddevid/…, MIT), NOT recolors of Classic: own road
  // hierarchy, own POI chip system, own label ladder. Same enum slots as
  // the retired v6.4 paint-rewrites (porcelain/obsidian) → persisted
  // indices keep their meaning.
  silk,
  onyx,
}

/// v6.8: the themes AUTO-NIGHT is allowed to paint = the dark slice of the
/// catalog, minus satellite (a photo basemap cannot be "made night"). The
/// list lives here rather than next to [kMapStyleCatalog] because
/// map_catalog.dart already imports this library.
bool isNightCapable(MapStyle s) => switch (s) {
  MapStyle.noir ||
  MapStyle.onyx ||
  MapStyle.midnight ||
  MapStyle.amethyst ||
  MapStyle.emerald ||
  MapStyle.abyss ||
  MapStyle.espresso => true,
  _ => false,
};

/// v5.4: persisted map camera (the app must reopen WHERE THE USER CLOSED
/// IT — «всегда открывается париж» is a bug, not a default).
class LuxCam {
  const LuxCam({
    required this.lat,
    required this.lon,
    required this.zoom,
    this.bearing = 0,
    this.tilt = 0,
  });

  final double lat, lon, zoom, bearing, tilt;

  Map<String, Object> toJson() => {
    'lat': lat,
    'lon': lon,
    'zoom': zoom,
    'bearing': bearing,
    'tilt': tilt,
  };

  factory LuxCam.fromJson(Map<String, dynamic> j) => LuxCam(
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    zoom: (j['zoom'] as num?)?.toDouble() ?? 14,
    bearing: (j['bearing'] as num?)?.toDouble() ?? 0,
    tilt: (j['tilt'] as num?)?.toDouble() ?? 0,
  );
}

/// v5.8: premium palette for FAVORITE pins — the user picks the color when
/// saving («цветные булавки избранного»). Indices are a persisted format.
const List<Color> kFavPinColors = [
  Color(0xFFF2A93B), // amber (classic favorite)
  Color(0xFF22A35F), // green
  Color(0xFFE2452F), // red
  Color(0xFF1FA9A0), // teal
  Color(0xFF7C5CE0), // violet
  Color(0xFFE36BA0), // rose
];

/// A saved / selected place.
class LuxPlace {
  const LuxPlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.subtitle = '',
    this.kind = 'place',
    this.colorIdx = 0,
    this.distanceKm,
  });

  final String name;
  final String subtitle;
  final double lat, lon;
  final String kind; // place | home | work | favorite | poi

  /// v5.8: pin color index for favorites (kFavPinColors).
  final int colorIdx;

  /// v6.7: straight-line distance to the search anchor, set only by
  /// geocoding. Transient — saving a place must not freeze a distance.
  final double? distanceKm;

  Map<String, Object> toJson() => {
    'name': name,
    'subtitle': subtitle,
    'lat': lat,
    'lon': lon,
    'kind': kind,
    if (colorIdx != 0) 'color': colorIdx,
  };

  factory LuxPlace.fromJson(Map<String, dynamic> j) => LuxPlace(
    name: (j['name'] ?? '') as String,
    subtitle: (j['subtitle'] ?? '') as String,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    kind: (j['kind'] ?? 'place') as String,
    colorIdx: (j['color'] as num?)?.toInt() ?? 0,
  );

  LuxPlace copyWith({
    String? name,
    String? subtitle,
    String? kind,
    int? colorIdx,
  }) => LuxPlace(
    name: name ?? this.name,
    subtitle: subtitle ?? this.subtitle,
    lat: lat,
    lon: lon,
    kind: kind ?? this.kind,
    colorIdx: colorIdx ?? this.colorIdx,
  );
}

/// Navigation state machine: idle → routing → preview → navigating → arrived.
enum NavPhase { idle, routing, preview, navigating, rerouting, arrived }

class AppState extends ChangeNotifier {
  AppState() {
    _load();
  }

  late SharedPreferences _prefs;

  /// v5.4: true once persisted settings are in memory. The root widget
  /// gates the UI behind a splash until this flips, so the map is created
  /// with the RESTORED camera — no Paris flash on every start.
  bool loaded = false;

  // ── Settings ──────────────────────────────────────────────────────────
  LuxTheme theme = kLuxThemes.first;
  // v6.2: English is the default first-launch language.
  Locale locale = kEn;
  bool metric = true;
  MapStyle mapStyle = MapStyle.classic;

  /// v6.6 THE PREMIUM RENDER FAMILY («все наши цвета карт перенести на
  /// новые»): when true, the ACTIVE map theme is drawn by the Atlas engine
  /// (the v6.5 Apple-Maps-like cartography — POI chips, own road hierarchy,
  /// own label ladder) repainted into that theme's OWN palette. The colors
  /// stay the user's; only the RENDERING changes. Satellite/relief are
  /// imagery and always render as themselves.
  bool premiumRender = false;

  /// v5.9: flat footprints by default (the user asked for "обычные" houses
  /// and the freedom to switch to 3D himself).
  BuildingsMode buildingsMode = BuildingsMode.flat;
  bool voiceOn = true;

  /// v6.8: which speaker reads the prompts. `auto` = the downloaded offline
  /// voice when this language has one, else the phone's own TTS; `system` and
  /// `offline` force a speaker. Offline is what makes guidance work on a
  /// device with no Google speech services (microG).
  String voiceEngine = 'auto';
  TravelMode mode = TravelMode.car;

  // ── v5.5: route options («быстрее/короче, платные/бесплатные…») ────────
  RoutePref routePref = RoutePref.fast;
  bool avoidTolls = false;
  bool avoidMotorways = false;
  bool avoidFerries = false;

  // ── v5.6: the moving marker (стрелка / машина / велосипед / человек) ───
  PuckPref puckPref = PuckPref.auto;

  /// The marker kind for the CURRENT settings (drives the map layer).
  PuckKind get puckKind => resolvePuck(puckPref, mode);

  // ── v5.8: driving-assist settings ────────────────────────────────────
  /// Haptic feedback on maneuvers / camera alerts.
  bool hapticsOn = true;

  /// Speed camera warnings (OSM data, keyless).
  bool camWarnOn = true;

  /// The map dims itself after sunset and returns after dawn.
  bool autoNightOn = true;

  /// v6.7: AUTO-NIGHT is a RENDER-TIME shade, not a theme change. [mapStyle]
  /// always keeps the theme the user actually picked; while it is night the
  /// basemap draws [renderedStyle] instead. Nothing here is persisted, so
  /// neither a restart nor the dawn can leave him on a theme he never chose
  /// (the «был Оникс, стал Нуар» report).
  bool nightShade = false;

  /// v6.8: which dark theme the AUTO-NIGHT shade paints. Chosen by the user
  /// in Settings → Карта; [mapStyle] (his day theme) is never touched, so
  /// dawn hands back exactly what he left.
  MapStyle nightStyle = MapStyle.noir;

  /// The theme the basemap must draw right now.
  MapStyle get renderedStyle => nightShade ? nightStyle : mapStyle;

  /// v6: internet enrichment of place cards (photos / description / flag /
  /// emblem from Wikipedia + Wikidata + Commons). The user asked for a
  /// toggle: «для нее тумблер сделай чтобы отключить можно было для тех
  /// кому она не нужна или она жрет инет».
  bool onlineInfoOn = true;

  // ── Places ────────────────────────────────────────────────────────────
  LuxPlace? home, work;
  final List<LuxPlace> favorites = [];

  // ── v5.8: recent destinations (история поездок) ────────────────────────
  final List<LuxPlace> recents = [];

  /// Adds a destination to the history (deduped by name+coords, max 12).
  Future<void> addRecent(LuxPlace p) async {
    recents.removeWhere(
      (r) => r.name == p.name && (r.lat - p.lat).abs() < 1e-5,
    );
    recents.insert(0, p.copyWith(kind: 'place'));
    if (recents.length > 12) recents.removeRange(12, recents.length);
    await _prefs.setString(
      'lux.recents',
      jsonEncode(recents.map((r) => r.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> clearRecents() async {
    recents.clear();
    await _prefs.remove('lux.recents');
    notifyListeners();
  }

  // ── v5.4: last known camera / GPS fix (persisted) ────────────────────
  LuxCam? lastCamera;
  LuxCam? lastGps;

  /// The vector theme to return to when Спутник / Рельеф is switched off
  /// in the layers sheet. v5.6 FIX (the user: «выбираю спутник и когда его
  /// отключаю карта сбивается включается классическая»): the value is now
  /// PERSISTED — it used to reset to classic on every app start, so turning
  /// the satellite OFF always fell back to Classic instead of the theme the
  /// user actually had.
  MapStyle _preVector = MapStyle.classic;
  MapStyle get lastVectorStyle => _preVector;

  /// v5.4: layers sheet toggles for the two raster basemap types. Turning
  /// one on switches the map style to it; turning it off restores the last
  /// vector theme (themes themselves live in Settings).
  Future<void> toggleBasemap(MapStyle type) async {
    if (mapStyle == type) {
      await setMapStyle(_preVector);
    } else {
      if (type != MapStyle.satellite && type != MapStyle.relief) {
        _preVector = type;
      }
      await setMapStyle(type);
    }
    // Remember the vector theme across restarts (see the v5.6 fix above).
    await _prefs.setInt('lux.preVector', _preVector.index);
  }

  // ── Selection / routing ───────────────────────────────────────────────
  LuxPlace? destination;

  /// v5.3: explicit route START (from the planner). null → start from the
  /// device location. A non-null origin that is NOT the device location
  /// allows previewing the route but not turn-by-turn guidance.
  LuxPlace? routeOrigin;

  /// v5.8: intermediate stops of the CURRENT plan (A → B → C → D). Kept in
  /// state so «Начать» re-fetches the SAME multi-stop route.
  List<LuxPlace> routeStops = const [];
  NavPhase navPhase = NavPhase.idle;
  String? routeError;
  double routeMeters = 0;
  double routeSeconds = 0;
  List<List<double>> routeLine = [];
  List<List<double>> traveledLine = [];
  String? arrivalTitle;
  double remainingMeters = 0;
  double remainingSeconds = 0;

  /// Maneuver key of the CURRENT navigation step (drives the HUD glyph).
  String currentManeuver = 'straight';

  // ── v5.5: route variants + road incidents ──────────────────────────────
  /// Alternative routes returned by the router (fastest / shorter, with and
  /// without tolls…). [showPreview] fills it; [selectAlt] switches.
  List<RouteAlt> routeAlts = const [];
  int selectedAlt = 0;

  /// Roadworks / closures found along the route (OpenStreetMap, best
  /// effort). 0 → nothing found; -1 → the lookup is still running.
  int incidentsCount = 0;

  // ── v5.7: public transport (общественный транспорт) ──────────────────
  /// The itineraries the Transitous router returned (list of departure
  /// options). Filled by the transit flow; cleared in [resetRoute].
  List<TransitItinerary> transitOptions = const [];

  /// The itinerary DRAWN on the map and (during follow) being ridden.
  TransitItinerary? transitPlan;

  /// Index of the leg the rider is currently on (HUD + notifications).
  int transitLeg = 0;

  /// v5.7: metres from the rider to the current leg's exit/transfer point
  /// (fed by the TransitSession on every fix; HUD display only).
  double transitStopM = 0;

  // ── v5.8: driving-assist live state ───────────────────────────────────
  /// When the guidance started (elapsed time in the HUD + arrival card).
  DateTime? navStartedAt;

  /// Arrival-card stats (frozen by [arrive]).
  double tripMeters = 0;
  double tripSeconds = 0;

  /// Live speed of the last GPS fix, km/h (HUD speedometer).
  double speedKmh = 0;

  // ── v5.9: navigation HUD compact top strip + sheet ────────────────────
  /// Device-compass heading (0° = north, clockwise) from the magnetometer —
  /// the IDLE arrow spins with the phone («стрелка крутилась по сторонам
  /// север запад юг восток в зависимости куда я поверну телефон»). null →
  /// the sensor is absent and GPS course is used.
  double? deviceHeading;

  /// Street of the CURRENT maneuver step (compact HUD line).
  String maneuverStreet = '';

  /// Distance to the CURRENT maneuver (compact HUD line, metres).
  double maneuverDistanceM = 0;

  /// Legal speed limit of the current road (OSM maxspeed via Overpass);
  /// null → unknown, the badge hides.
  int? speedLimitKmh;
  DateTime speedLimitAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Active camera warning (null → none).
  CamAlert? camAlert;

  /// True when the transport profile is active.
  bool get isTransit => mode == TravelMode.transit;

  /// True when the current road limit is exceeded (Google-Maps tolerance:
  /// +4 km/h so GPS jitter never turns the badge red at the legal speed).
  bool get isOverspeed {
    final lim = speedLimitKmh;
    if (lim == null) return false;
    return speedKmh > lim + 4;
  }

  void setShowAlternatives(List<RouteAlt> alts, int preferred) {
    routeAlts = alts;
    selectedAlt = preferred.clamp(0, alts.isEmpty ? 0 : alts.length - 1);
    if (alts.isNotEmpty) {
      final a = alts[selectedAlt];
      routeMeters = a.meters;
      routeSeconds = a.seconds;
      routeLine = a.line;
    }
    notifyListeners();
  }

  /// Switches the displayed variant; returns the selected one (or null when
  /// nothing changed).
  RouteAlt? selectAlt(int i) {
    if (i < 0 || i >= routeAlts.length || i == selectedAlt) return null;
    selectedAlt = i;
    final a = routeAlts[i];
    routeMeters = a.meters;
    routeSeconds = a.seconds;
    routeLine = a.line;
    traveledLine = [];
    notifyListeners();
    return a;
  }

  /// v5.5: incidents lookup lifecycle (kept here so the UI never touches
  /// the protected notifyListeners).
  void setIncidentsChecking() {
    incidentsCount = -1;
    notifyListeners();
  }

  void setIncidentsFound(int n) {
    incidentsCount = n;
    notifyListeners();
  }

  /// v5.1: exactly two app looks (light / dark) — no system-follow option.
  LuxTheme get effectiveTheme => theme;

  // ── Persistence ───────────────────────────────────────────────────────
  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final id = _prefs.getString('lux.theme');
    // luxThemeById maps any pre-5.1 palette id (graphite/noir/…) onto the
    // matching LIGHT or DARK app look.
    theme = luxThemeById(id ?? 'day');
    final lang = _prefs.getString('lux.lang');
    if (lang != null) S.current = Locale(lang);
    locale = S.current;
    metric = _prefs.getBool('lux.metric') ?? true;
    final savedStyle = _prefs.getInt('lux.mapStyle');
    if (savedStyle != null) {
      mapStyle = MapStyle.values.asMap()[savedStyle] ?? MapStyle.classic;
    } else {
      // Legacy (≤5.0) indices: 0 scheme, 1 satellite, 2 relief, 3 night.
      // v6.6.1: relief left the app, so the old relief slot restores Classic.
      mapStyle = switch (_prefs.getInt('lux.mapType')) {
        1 => MapStyle.satellite,
        3 => MapStyle.noir,
        _ => MapStyle.classic,
      };
    }
    // v5.6: restore the vector theme the satellite/relief toggles return to.
    final savedPre = _prefs.getInt('lux.preVector');
    _preVector =
        MapStyle.values.asMap()[savedPre ?? MapStyle.classic.index] ??
        MapStyle.classic;
    if (_preVector == MapStyle.satellite || _preVector == MapStyle.relief) {
      _preVector = MapStyle.classic; // never a raster theme
    }
    // v6.6.1: «рельеф убери» — the theme is gone from the catalog, so a
    // device that last used it comes back on its last vector theme.
    if (mapStyle == MapStyle.relief) mapStyle = _preVector;
    // v6.8: the night theme AUTO-NIGHT paints. Anything that is not a dark
    // vector theme (or a stale index from a future build) falls back to Noir.
    final savedNight = _prefs.getInt('lux.nightStyle');
    final nightCandidate = MapStyle.values.asMap()[savedNight ?? -1] ??
        MapStyle.noir;
    nightStyle = isNightCapable(nightCandidate)
        ? nightCandidate
        : MapStyle.noir;
    // v5.9: buildings mode with legacy migration (the old 3D bool).
    buildingsMode = switch (_prefs.getString('lux.buildings')) {
      'flat' => BuildingsMode.flat,
      'threeD' => BuildingsMode.threeD,
      'off' => BuildingsMode.off,
      // ≤5.8 stored only the extrusion toggle; keep the user's choice.
      _ =>
        (_prefs.getBool('lux.3d') ?? false)
            ? BuildingsMode.threeD
            : BuildingsMode.flat,
    };
    voiceOn = _prefs.getBool('lux.voice') ?? true;
    voiceEngine = switch (_prefs.getString('lux.voiceEngine')) {
      'system' => 'system',
      'offline' => 'offline',
      _ => 'auto',
    };
    puckPref = switch (_prefs.getString('lux.puck')) {
      'arrow' => PuckPref.arrow,
      'car' => PuckPref.car,
      'dot' => PuckPref.dot,
      _ => PuckPref.auto,
    };
    routePref = (_prefs.getString('lux.pref') == 'short')
        ? RoutePref.short
        : RoutePref.fast;
    avoidTolls = _prefs.getBool('lux.noToll') ?? false;
    avoidMotorways = _prefs.getBool('lux.noMw') ?? false;
    avoidFerries = _prefs.getBool('lux.noFerry') ?? false;
    hapticsOn = _prefs.getBool('lux.haptics') ?? true;
    camWarnOn = _prefs.getBool('lux.cams') ?? true;
    autoNightOn = _prefs.getBool('lux.autoNight') ?? true;
    onlineInfoOn = _prefs.getBool('lux.onlineInfo') ?? true;
    home = _place('lux.home');
    work = _place('lux.work');
    favorites
      ..clear()
      ..addAll(
        (jsonDecode(_prefs.getString('lux.favs') ?? '[]') as List)
            .whereType<Map<String, dynamic>>()
            .map(LuxPlace.fromJson),
      );
    recents
      ..clear()
      ..addAll(
        (jsonDecode(_prefs.getString('lux.recents') ?? '[]') as List)
            .whereType<Map<String, dynamic>>()
            .map(LuxPlace.fromJson),
      );
    lastCamera = _cam('lux.cam');
    lastGps = _cam(
      'lux.gps2',
    ); // v6.4: fresh key — the old one may hold the poisoned stale-cache fix
    // v6.6.1: Atlas is the default RENDERING for every color theme now («все
    // цвета тем на новом оформлении»). New key so the older, saved "off"
    // choice does not outlive the decision; the toggle still persists.
    premiumRender = _prefs.getBool('lux.premiumRender2') ?? true;
    loaded = true;
    notifyListeners();
  }

  LuxCam? _cam(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return LuxCam.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// v5.4: persist the camera on every idle movement + on app pause, so the
  /// next start opens exactly where the user left («на каком участке
  /// закрыл приложение или свернул»).
  Future<void> saveCamera(LuxCam c) async {
    lastCamera = c;
    await _prefs.setString('lux.cam', jsonEncode(c.toJson()));
  }

  /// v5.4: remember the last real GPS fix as a secondary restore point (a
  /// saved camera is always preferred, but the fix helps a fresh install).
  Future<void> saveGpsFix(double lat, double lon, {double zoom = 14.5}) async {
    lastGps = LuxCam(lat: lat, lon: lon, zoom: zoom);
    await _prefs.setString('lux.gps2', jsonEncode(lastGps!.toJson()));
  }

  LuxPlace? _place(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return LuxPlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePlace(String key, LuxPlace? p) async {
    if (p == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, jsonEncode(p.toJson()));
    }
  }

  // ── Mutators ──────────────────────────────────────────────────────────
  Future<void> setTheme(LuxTheme t) async {
    theme = t;
    await _prefs.setString('lux.theme', t.id);
    notifyListeners();
  }

  Future<void> setLocale(Locale l) async {
    locale = l;
    S.current = l;
    await _prefs.setString('lux.lang', l.languageCode);
    notifyListeners();
  }

  Future<void> setMetric(bool v) async {
    metric = v;
    await _prefs.setBool('lux.metric', v);
    notifyListeners();
  }

  /// v6.6: [premium] pins the rendering family together with the theme (the
  /// picker passes it so «Аметист в Классике» and «Аметист в Премиуме» are
  /// two distinct choices). Callers that omit it keep the current family.
  Future<void> setMapStyle(MapStyle s, {bool? premium}) async {
    mapStyle = s;
    // v6.7: a deliberate pick always wins over the transient night shade —
    // the next AUTO-NIGHT tick re-decides if it is still night.
    nightShade = false;
    if (premium != null) premiumRender = premium;
    if (s != MapStyle.satellite && s != MapStyle.relief) _preVector = s;
    await _prefs.setInt('lux.mapStyle', s.index);
    await _prefs.setBool('lux.premiumRender2', premiumRender);
    await _prefs.setInt('lux.preVector', _preVector.index);
    notifyListeners();
  }

  /// v6.7: AUTO-NIGHT's transient dark drawing. Deliberately NOT persisted:
  /// [mapStyle] stays the user's own theme.
  void setNightShade(bool v) {
    if (nightShade == v) return;
    nightShade = v;
    notifyListeners();
  }

  /// v6.8: the dark theme AUTO-NIGHT paints at night. Changing it while the
  /// shade is already on re-renders the basemap immediately (the render
  /// signature carries [renderedStyle]).
  Future<void> setNightStyle(MapStyle s) async {
    if (!isNightCapable(s) || nightStyle == s) return;
    nightStyle = s;
    await _prefs.setInt('lux.nightStyle', s.index);
    notifyListeners();
  }

  /// v6.6: switch the rendering family for the CURRENT theme.
  Future<void> setPremiumRender(bool v) async {
    if (premiumRender == v) return;
    premiumRender = v;
    await _prefs.setBool('lux.premiumRender2', v);
    notifyListeners();
  }

  /// v5.9: buildings render mode (Обычные / 3D / Выкл).
  Future<void> setBuildingsMode(BuildingsMode m) async {
    buildingsMode = m;
    await _prefs.setString('lux.buildings', m.name);
    notifyListeners();
  }

  Future<void> setVoice(bool v) async {
    voiceOn = v;
    await _prefs.setBool('lux.voice', v);
    notifyListeners();
  }

  /// v6.8: system TTS vs. the downloaded offline voice.
  Future<void> setVoiceEngine(String e) async {
    voiceEngine = e;
    await _prefs.setString('lux.voiceEngine', e);
    notifyListeners();
  }

  /// v6.8: a voice finished downloading (or was removed). Nothing of ours
  /// changed — the settings «кто озвучивает» line did, and it is built from
  /// AppState notifications.
  void touchVoice() => notifyListeners();

  // ── v5.5 route options mutators ────────────────────────────────────────
  Future<void> setRoutePref(RoutePref p) async {
    routePref = p;
    await _prefs.setString('lux.pref', p.name);
    notifyListeners();
  }

  Future<void> setAvoidTolls(bool v) async {
    avoidTolls = v;
    await _prefs.setBool('lux.noToll', v);
    notifyListeners();
  }

  Future<void> setAvoidMotorways(bool v) async {
    avoidMotorways = v;
    await _prefs.setBool('lux.noMw', v);
    notifyListeners();
  }

  Future<void> setAvoidFerries(bool v) async {
    avoidFerries = v;
    await _prefs.setBool('lux.noFerry', v);
    notifyListeners();
  }

  // ── v5.8 driving-assist mutators ───────────────────────────────────────
  Future<void> setHaptics(bool v) async {
    hapticsOn = v;
    await _prefs.setBool('lux.haptics', v);
    notifyListeners();
  }

  Future<void> setCamWarn(bool v) async {
    camWarnOn = v;
    if (!v) camAlert = null;
    await _prefs.setBool('lux.cams', v);
    notifyListeners();
  }

  Future<void> setAutoNight(bool v) async {
    autoNightOn = v;
    await _prefs.setBool('lux.autoNight', v);
    notifyListeners();
  }

  /// v6: master switch for the online place-card enrichment.
  Future<void> setOnlineInfo(bool v) async {
    onlineInfoOn = v;
    await _prefs.setBool('lux.onlineInfo', v);
    notifyListeners();
  }

  Future<void> setMode(TravelMode m) async {
    mode = m;
    notifyListeners();
  }

  // ── v5.6: the moving marker ─────────────────────────────────────────────
  Future<void> setPuckPref(PuckPref p) async {
    puckPref = p;
    await _prefs.setString('lux.puck', p.name);
    notifyListeners();
  }

  Future<void> setHome(LuxPlace? p) async {
    home = p;
    await _savePlace('lux.home', p);
    notifyListeners();
  }

  Future<void> setWork(LuxPlace? p) async {
    work = p;
    await _savePlace('lux.work', p);
    notifyListeners();
  }

  Future<void> toggleFavorite(LuxPlace p, {int colorIdx = 0}) async {
    final i = favorites.indexWhere(
      (f) => (f.name == p.name) && (f.lat - p.lat).abs() < 1e-6,
    );
    if (i >= 0) {
      favorites.removeAt(i);
    } else {
      favorites.insert(0, p.copyWith(kind: 'favorite', colorIdx: colorIdx));
    }
    await _prefs.setString(
      'lux.favs',
      jsonEncode(favorites.map((f) => f.toJson()).toList()),
    );
    notifyListeners();
  }

  bool isFavorite(LuxPlace p) =>
      favorites.any((f) => f.name == p.name && (f.lat - p.lat).abs() < 1e-6);

  /// v5.3: removing saved places from the Favorites window (the user asked
  /// «поставленную избранную точку как убрать?»). [removeSaved] handles
  /// home / work / favorites uniformly and returns true when something was
  /// actually removed.
  Future<bool> removeSaved(LuxPlace p) async {
    if (home != null &&
        (home!.lat - p.lat).abs() < 1e-6 &&
        home!.kind == p.kind) {
      await setHome(null);
      return true;
    }
    if (work != null &&
        (work!.lat - p.lat).abs() < 1e-6 &&
        work!.kind == p.kind) {
      await setWork(null);
      return true;
    }
    final i = favorites.indexWhere(
      (f) => (f.lat - p.lat).abs() < 1e-6 && (f.lon - p.lon).abs() < 1e-6,
    );
    if (i >= 0) {
      favorites.removeAt(i);
      await _prefs.setString(
        'lux.favs',
        jsonEncode(favorites.map((f) => f.toJson()).toList()),
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Navigation state ──────────────────────────────────────────────────
  void beginRouting() {
    navPhase = NavPhase.routing;
    routeError = null;
    notifyListeners();
  }

  void showPreview({
    required double meters,
    required double seconds,
    required List<List<double>> line,
    LuxPlace? origin,
    List<RouteAlt> alts = const [],
    int preferredAlt = 0,
  }) {
    navPhase = NavPhase.preview;
    routeMeters = meters;
    routeSeconds = seconds;
    remainingMeters = meters;
    remainingSeconds = seconds;
    routeLine = line;
    traveledLine = [];
    routeOrigin = origin;
    routeError = null;
    routeAlts = alts;
    selectedAlt = preferredAlt.clamp(0, alts.isEmpty ? 0 : alts.length - 1);
    incidentsCount = 0; // re-probed after the line is drawn
    notifyListeners();
  }

  void failRouting(String msg) {
    navPhase = NavPhase.idle;
    routeError = msg;
    routeLine = [];
    traveledLine = [];
    notifyListeners();
  }

  void startNavigating() {
    navPhase = NavPhase.navigating;
    // v5.8: elapsed-time + average-speed bookkeeping for the HUD/summary.
    navStartedAt = DateTime.now();
    notifyListeners();
  }

  void rerouting() {
    if (navPhase == NavPhase.navigating) navPhase = NavPhase.rerouting;
    notifyListeners();
  }

  void backToPreview() {
    navPhase = NavPhase.preview;
    notifyListeners();
  }

  void updateProgress(
    double remainM,
    double remainS,
    List<List<double>> traveled,
  ) {
    remainingMeters = remainM;
    remainingSeconds = remainS;
    traveledLine = traveled;
    notifyListeners();
  }

  /// v5.8: public repaint pulse for the driving-assist fields (speed limit,
  /// camera alert) — the GPS feed sets them directly and asks for one
  /// controlled notifyListeners afterwards.
  void pulseAssist() => notifyListeners();

  void arrive() {
    navPhase = NavPhase.arrived;
    // v5.8: premium arrival summary — freeze the trip stats.
    tripMeters = (routeMeters - remainingMeters).clamp(0, routeMeters);
    tripSeconds = navStartedAt == null
        ? 0
        : DateTime.now().difference(navStartedAt!).inSeconds.toDouble();
    notifyListeners();
  }

  void resetRoute() {
    navPhase = NavPhase.idle;
    destination = null;
    routeOrigin = null;
    routeStops = const [];
    routeError = null;
    routeLine = [];
    traveledLine = [];
    routeAlts = const [];
    selectedAlt = 0;
    incidentsCount = 0;
    arrivalTitle = null;
    currentManeuver = 'straight';
    transitOptions = const [];
    transitPlan = null;
    transitLeg = 0;
    // v5.8: driving-assist live state lives and dies with the route.
    navStartedAt = null;
    tripMeters = 0;
    tripSeconds = 0;
    speedKmh = 0;
    speedLimitKmh = null;
    camAlert = null;
    maneuverStreet = '';
    maneuverDistanceM = 0;
    notifyListeners();
  }

  void setDestination(LuxPlace? p) {
    destination = p;
    notifyListeners();
  }

  // ── v5.7: transit state machine ────────────────────────────────────
  /// Shows the fetched itineraries and draws the preferred one.
  void showTransitOptions(List<TransitItinerary> list, {int preferred = 0}) {
    transitOptions = list;
    transitPlan = list.isEmpty
        ? null
        : list[preferred.clamp(0, list.length - 1)];
    transitLeg = 0;
    if (transitPlan != null) {
      navPhase = NavPhase.preview;
      routeError = null;
      // Keep routeLine in sync so the map-restore path works for transit too.
      routeLine = [for (final l in transitPlan!.legs) ...l.points];
      routeMeters = transitPlan!.meters;
      routeSeconds = transitPlan!.durationSec.toDouble();
      remainingMeters = routeMeters;
      remainingSeconds = routeSeconds;
    }
    notifyListeners();
  }

  /// Switches the itinerary drawn on the map; returns the selected one.
  TransitItinerary? selectTransitPlan(int i) {
    if (i < 0 ||
        i >= transitOptions.length ||
        transitPlan == transitOptions[i]) {
      return null;
    }
    transitPlan = transitOptions[i];
    transitLeg = 0;
    routeLine = [for (final l in transitPlan!.legs) ...l.points];
    routeMeters = transitPlan!.meters;
    routeSeconds = transitPlan!.durationSec.toDouble();
    notifyListeners();
    return transitPlan;
  }

  /// Starts riding the chosen itinerary (HUD + notifications + TTS).
  void startTransit() {
    if (transitPlan == null) return;
    navPhase = NavPhase.navigating;
    transitLeg = 0;
    notifyListeners();
  }

  /// The rider boarded the next vehicle / started the next walk leg.
  void advanceTransitLeg(int i) {
    transitLeg = i;
    notifyListeners();
  }

  // ── Formatting helpers ────────────────────────────────────────────────
  String formatDistance(double meters) {
    if (metric) {
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} ${S.of('km')}';
      }
      return '${meters.round()} ${S.of('m')}';
    }
    final feet = meters * 3.28084;
    if (feet >= 5280) {
      return '${(feet / 5280).toStringAsFixed(feet >= 52800 ? 0 : 1)} mi';
    }
    return '${feet.round()} ft';
  }

  String formatDuration(double seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m ${S.of('min')}';
    final h = m ~/ 60;
    final mm = m % 60;
    return '$h ${S.of('h')} $mm ${S.of('min')}';
  }
}

/// v5.5: one route variant (geometry + totals only — steps are refetched
/// when guidance actually starts).
class RouteAlt {
  const RouteAlt({
    required this.meters,
    required this.seconds,
    required this.line,
    this.label,
    this.hasToll = false,
    this.hasHighway = false,
    this.hasFerry = false,
  });
  final double meters, seconds;
  final List<List<double>> line;

  /// Optional engine hint: 'fast' | 'short' (index 0 is the fastest one).
  final String? label;

  /// Badges (from the Valhalla summary; OSRM leaves them false).
  final bool hasToll, hasHighway, hasFerry;
}
