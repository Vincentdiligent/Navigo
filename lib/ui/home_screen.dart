/// The main screen: one clean map-first surface.
///
/// Overlay budget (learned from v1/v2 feedback): a single search pill row,
/// one control capsule on the right, one travel-mode capsule bottom-left and
/// ONE bottom panel that swaps content. Nothing else.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/geo_math.dart';
import '../core/lux_theme.dart';
import '../core/strings.dart';
import '../core/suncalc.dart';
import '../map/location_stream.dart';
import '../map/map_catalog.dart';
import '../map/map_engine.dart';
import '../map/style_pack.dart';
import '../places/geocoding.dart';
import '../places/photo_cache.dart';
import '../route/incidents.dart';
import '../route/nav_notifications.dart';
import '../route/nav_session.dart';
import '../route/overpass.dart';
import '../route/route_service.dart';
import '../route/speed_cameras.dart';
import '../route/speed_limits.dart';
import '../route/transit_model.dart';
import '../route/transit_service.dart';
import '../route/transit_session.dart';
import '../route/voice.dart';
import 'layers_sheet.dart';
import 'place_sheet.dart';
import 'route_panel.dart';
import 'route_planner_sheet.dart';
import 'saved_sheet.dart';
import 'search_page.dart';
import 'settings_sheet.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final MapEngine engine = MapEngine();
  final LocationStream location = LocationStream();
  final RouteService routes = RouteService();
  final Geocoding geocoding = Geocoding();
  // v5.5: roadworks / closures along the active route (best effort).
  final IncidentService incidents = IncidentService();

  /// v6.1: incident points of the CURRENT route preview — the wake rebuild
  /// re-creates the map view, and this is what goes back onto it.
  List<List<double>> _lastIncidentPts = const [];
  // v5.7: public transport (Transitous — keyless GTFS routing).
  final TransitService transit = TransitService();
  // v5.8: SPEED LIMITS + SPEED CAMERAS (OpenStreetMap via Overpass,
  // keyless — the same data OsmAnd rides on).
  final Overpass overpass = Overpass();
  late final SpeedLimitEngine limits = SpeedLimitEngine(overpass);
  late final CameraService cameras = CameraService(overpass);
  NavVoice? voice;
  NavSession? nav;
  TransitSession? transitRide;

  // v5.8: auto-night (карта темнеет по закату). v6.7: the shade is a
  // render-time overlay on AppState — the user's saved theme is never
  // rewritten, so nothing has to be "restored" and nothing sticks.
  Timer? _autoNightTimer;

  // v5.7: route overview while navigating («нужен маршрут отдельно чтобы
  // посмотреть») — true after the user tapped the map button; any tap on
  // the recenter button or a fresh follow restores the camera.
  bool _navOverview = false;

  // v5.7: notification throttle — the FGS notification is re-posted at
  // most once per 2.5 s unless the MANEUVER changed.
  String _notifSig = '';
  Timer? _notifThrottle;

  /// v5.5→v5.6: one modal sheet at a time PER KIND — the tagged guard in
  /// widgets.dart blocks the same sheet twice (the user's duplicate-window
  /// bug) while allowing NESTED sheets (Настройки → Темы, Оффлайн, поиск).
  /// [_sheetBusy] here is only the short tap-lock for the async gap between
  /// the map tap and the sheet actually appearing.
  bool _sheetBusy = false;
  int _incidentToken = 0;

  /// v5.5: the buildings MODE is applied to the LIVE map on every state
  /// change (v5.4 only applied it on the next style reload).
  BuildingsMode? _appliedBld;

  // v5.9: device-compass stream — the IDLE arrow turns N/W/S/E with the
  // phone («стрелка крутилась по сторонам север запад юг восток в
  // зависимости куда я поверну телефон»).
  StreamSubscription<CompassEvent>? _compassSub;
  double? _lastAppliedHeading;

  bool gpsReady = false;
  // v5.4: the REAL default is set in _boot from the persisted camera/GPS —
  // Paris is only the fresh-install fallback, never the every-start one.
  double lat = 48.8566, lon = 2.3522;
  double zoom0 = 12.5;
  double heading = 0;

  // v5.1 CAMERA CONTRACT: the map NEVER drags itself back to the user while
  // the user is browsing. The camera follows the finger — period. One-time
  // centering happens on the very first GPS fix; afterwards only the
  // recenter button (or an active navigation session) may move the camera.
  bool followMe = false; // true → recenter button shows the "pinned" state
  bool _didInitialCenter = false;
  bool _cameraProgrammatic = false; // our own animations ≠ user gestures
  Timer? _followDebounce;

  /// Camera bearing for the custom compass button.
  double _bearing = 0;

  /// AppState bound in _boot — needed to detach the listener in dispose.
  AppState? _boundState;

  // ── Style loading state machine ───────────────────────────────────
  // The style is a hosted document; if it does not finish loading (network
  // outage, provider hiccup) the user must never stare at a dead map.
  // Pre-flight probe → watchdog → simplified raster mode → explicit error
  // card with retry — and AUTO-RECOVERY when the network comes back.
  bool _useFallback = false; // simplified raster basemap after failures
  bool _fatal = false; // primary AND fallback both failed to load
  bool _everLoaded = false; // first successful style load happened
  String _pendingSig = '';
  String _loadedSig = '';
  Timer? _watchdog;
  Timer? _autoRecover;

  // ── v6.5 FADE-IN MASKING («настоящее лечение мелькания») ─────────────
  // The blink was never a style problem: it is the platform view's
  // LIFECYCLE leaking through — the blank frame when a native MapView is
  // created (app start AND the wake rebuild), and the style-swap moment.
  // The fix is to MASK the lifecycle, not to fight the renderer: an
  // opaque scrim in the theme's land color covers the map, then FADES
  // OUT once the style has loaded and the first tiles have landed — the
  // map «проявляется» instead of вспыхивать. Works for BOTH renderers
  // (the Settings toggle stays a pure A/B experiment).
  bool _scrimUp = true; // a cover pass is active (incl. the fade)
  bool _scrimSolid = true; // fully opaque; false → fading out
  String _scrimSig = ''; // style signature the scrim was armed for
  Timer? _scrimTimer;

  void _ensureWatchdog(String sig, {required bool fallback}) {
    if (_pendingSig == sig) return;
    _pendingSig = sig;
    _watchdog?.cancel();
    // Fallback mode is an inline raster doc — it needs no network to parse,
    // so an 8 s window is generous. Hosted vector styles get 12 s.
    _watchdog = Timer(
      Duration(seconds: fallback ? 8 : 12),
      () => _onStyleTimeout(sig),
    );
  }

  void _onStyleTimeout(String sig) {
    if (!mounted || _loadedSig == sig || _pendingSig != sig) return;
    final state = context.read<AppState>();
    if (!_useFallback && !_fatal) {
      setState(() {
        _useFallback = true;
        _pendingSig = ''; // re-armed with the fallback signature in build
      });
      engine.prepareLayers(state, fallback: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('simpleModeOn')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (!_fatal) {
      setState(() => _fatal = true);
      _startAutoRecover();
    }
  }

  /// v5: while the fatal card is up, keep probing the network every 20 s —
  /// the moment a hosted style becomes reachable the map comes back ON ITS
  /// OWN, no “Повторить” hunting required.
  void _startAutoRecover() {
    _autoRecover?.cancel();
    _autoRecover = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || !_fatal) return;
      final state = context.read<AppState>();
      if (await engine.probePrimary(state)) {
        if (!mounted) return;
        setState(() {
          _fatal = false;
          _useFallback = false;
          _loadedSig = '';
          _pendingSig = ''; // re-armed in build
        });
        _autoRecover?.cancel();
        _autoRecover = null;
        await engine.prepareLayers(state, fallback: false);
      }
    });
  }

  void _markLoaded(String sig) {
    _loadedSig = sig;
    _watchdog?.cancel();
    _autoRecover?.cancel();
    _autoRecover = null;
    _revealMap(); // v6.5: fade the cover away — the map «проявляется»
    if (!mounted) return;
    setState(() => _everLoaded = true);
  }

  /// v6.5: (re)arm the opaque cover — map creation, wake rebuild, theme
  /// switch, watchdog fallback. Cheap: one DecoratedBox.
  void _coverMap() {
    _scrimTimer?.cancel();
    _scrimTimer = null;
    if (!mounted) return;
    if (_scrimUp && _scrimSolid) return; // already covering
    setState(() {
      _scrimUp = true;
      _scrimSolid = true;
    });
  }

  /// v6.5: the reveal — a short hold (first tiles land), then a 340 ms
  /// fade to transparent, then the scrim unmounts completely.
  void _revealMap() {
    if (!mounted || !_scrimUp) return;
    _scrimTimer?.cancel();
    _scrimTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      setState(() => _scrimSolid = false);
      _scrimTimer = Timer(const Duration(milliseconds: 380), () {
        if (!mounted) return;
        setState(() => _scrimUp = false);
      });
    });
  }

  /// v6.5: the cover color is the ACTIVE MAP THEME's own land color —
  /// the reveal reads as the map fading in, not as a foreign overlay.
  Color _scrimColor(AppState state) {
    final info = mapStyleInfo(state.renderedStyle);
    if (info != null) return info.land;
    return state.effectiveTheme.background;
  }

  Future<void> _retryMap() async {
    final state = context.read<AppState>();
    _autoRecover?.cancel();
    _autoRecover = null;
    setState(() {
      _fatal = false;
      _useFallback = false;
      _loadedSig = '';
      _pendingSig = ''; // re-armed in build
    });
    await engine.prepareLayers(state, fallback: false);
  }

  Future<void> _forceSimpleMode() async {
    final state = context.read<AppState>();
    _autoRecover?.cancel();
    _autoRecover = null;
    setState(() {
      _fatal = false;
      _useFallback = true;
      _loadedSig = '';
      _pendingSig = '';
    });
    await engine.prepareLayers(state, fallback: true);
  }

  /// v5.4: camera-persist timers.
  Timer? _camSaveDebounce;
  Timer? _gpsSaveDebounce;
  bool _restoredCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // v5.4 CRITICAL: the native map consumes initialCameraPosition on the
    // VERY FIRST frame — the restored camera must be read synchronously
    // here, before the first build (AppState.loaded is already true, that
    // is guaranteed by the splash gate in app_shell).
    try {
      final state = context.read<AppState>();
      final cam = state.lastCamera ?? state.lastGps;
      if (cam != null) {
        lat = cam.lat;
        lon = cam.lon;
        zoom0 = cam.zoom.clamp(2.0, 19.0).toDouble();
        _restoredCamera = true;
      }
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  /// v6: the phone really went to the background (lock screen / sleep).
  /// v6.1 WAKE FIX v2 — HISTORY: v6.0 cured the dead-map-after-lock bug by
  /// rendering through a TextureView (translucentTextureSurface). That did
  /// fix the wake bug, but TextureView composites EVERY map frame through
  /// the Flutter GPU pipeline — the user got «сролл карты с тормозами…
  /// фризит!!». This release goes back to the NATIVE SurfaceView (Virtual
  /// Display — the fast path, the map renders through the hardware
  /// composer again) and cures the wake bug differently: a fresh native
  /// map view is built the moment the app truly resumes. A brand-new
  /// MapView CANNOT be “wall-eyed” — the old VirtualDisplay surface (the
  /// thing that died across the lock screen) is simply thrown away.
  /// The camera is captured live before the rebuild, so the map re-opens
  /// exactly where the user left it, and the onStyleLoaded flow restores
  /// routes / pins / favorites / cameras — the same machinery that already
  /// survives theme switches.
  bool _lifeWasPaused = false;

  /// v6.1: bumped on every wake rebuild — changes the MapLibreMap [key],
  /// which forces Flutter to create a brand-new native platform view.
  int _mapRev = 0;

  /// v6.1: the live camera captured at the moment of the wake rebuild —
  /// used as the initialCameraPosition of the fresh view (with bearing +
  /// tilt, unlike the boot camera which only restores target + zoom).
  ml.CameraPosition? _wakeCam;

  /// v6.4: a REAL fix has arrived this session (fresh cache hit, explicit
  /// acquisition or the live stream). NOTHING may present «my location»
  /// from Android's device-wide stale cache — that was the «то на речке,
  /// то в центре города» bug.
  bool _hasRealFix = false;

  /// v6.4: the round recenter button SPINS while the app searches for the
  /// user (boot acquisition or the button's own locate flow). The user:
  /// «круг справа в самом низу должен крутиться, когда ищет и когда я
  /// включаю местоположение, чтобы быстро меня найти».
  bool _locating = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // «запомнил моё последнее местоположение … там где я закрыл приложение
    // или свернул» — the camera and the GPS fix are persisted the moment
    // the app goes to background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _persistCameraNow();
      if (state == AppLifecycleState.paused) _lifeWasPaused = true;
    }
    // v5.8: on resume — re-check the auto-night (the sun does not wait).
    if (state == AppLifecycleState.resumed && mounted) {
      _checkAutoNight(context.read<AppState>());
      if (_lifeWasPaused) {
        _lifeWasPaused = false;
        _reviveMapAfterWake();
      }
    }
  }

  /// v6.1: rebuild the native map view after a real background round-trip
  /// (lock screen / sleep / biometric). Deterministic by construction:
  /// a NEW MapView is created, so the dead-surface class of bugs is gone —
  /// at the cost of a short re-render from the native tile cache (no
  /// network needed). Cheap, and it only happens after a wake.
  void _reviveMapAfterWake() {
    if (!mounted) return;
    final pos = engine.cameraPosition;
    // v6.5: the fresh native view starts blank — cover it until the
    // style reloads (the reveal happens in onStyleLoadedCallback).
    _scrimUp = true;
    _scrimSolid = true;
    setState(() {
      _mapRev++;
      if (pos != null) {
        _wakeCam = ml.CameraPosition(
          target: pos.target,
          zoom: pos.zoom,
          bearing: pos.bearing,
          tilt: pos.tilt,
        );
        lat = pos.target.latitude;
        lon = pos.target.longitude;
        zoom0 = pos.zoom;
      }
      // The signatures guard against REDUNDANT platform calls; the new
      // controller has not received any of that state yet — force re-push.
      _puckSig = '';
      _favSig = '';
    });
  }

  /// Runs a camera animation and hides it from the user-gesture detector.
  Future<void> _moveProgrammatic(Future<void> Function() move) async {
    _cameraProgrammatic = true;
    try {
      await move();
    } finally {
      // Trailing onCameraMove events of the animation must not be mistaken
      // for the user dragging the map.
      await Future<void>.delayed(const Duration(milliseconds: 320));
      _cameraProgrammatic = false;
    }
  }

  /// v6.4: the round recenter button — «должен крутиться, когда ищет, и
  /// когда я включаю местоположение, чтобы быстро меня найти». It spins
  /// from the tap until a TRUSTWORTHY position exists, then flies there.
  /// Never jumps to a device-wide stale cache: no fix → an honest snackbar.
  Future<void> _locateMe() async {
    _navOverview = false;
    final st = context.read<AppState>();
    if (mounted) setState(() => _locating = true);
    if (!gpsReady) {
      gpsReady = await location.ensurePermission();
      if (!mounted) return;
      if (!gpsReady) {
        setState(() => _locating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of('enableGps')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      location.listen(_onFix); // the stream may not be running pre-permission
    }
    if (!_hasRealFix) {
      // Fresh acquisition only — never the device-wide stale cache.
      final fix = await location.current();
      if (!mounted) return;
      if (fix != null) {
        setState(() {
          _hasRealFix = true;
          lat = fix.latitude;
          lon = fix.longitude;
        });
      }
    }
    if (!_hasRealFix) {
      // Nothing trustworthy — no random jumps, the spinner stops honestly.
      if (mounted) setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('enableGps')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (mounted) setState(() => followMe = true);
    await _moveProgrammatic(
      () => st.navPhase == NavPhase.navigating
          ? engine.navFollow(lat, lon, heading)
          : engine.moveTo(ml.LatLng(lat, lon), zoom: 15.5),
    );
    if (mounted) setState(() => _locating = false);
  }

  Future<void> _boot() async {
    final state = context.read<AppState>();
    // v6.4: the recenter button SPINS while the GPS story resolves.
    if (mounted) setState(() => _locating = true);
    // v5.4: restore the last session FIRST — the map must open where the
    // user closed it. Preference order: saved camera → last GPS fix →
    // fresh-install default (Paris).
    final cam = state.lastCamera ?? state.lastGps;
    if (cam != null && !_restoredCamera) {
      // Defensive duplicate of the initState restore (initState already
      // ran it; this only covers a hypothetical early failure there).
      setState(() {
        lat = cam.lat;
        lon = cam.lon;
        zoom0 = cam.zoom.clamp(2.0, 19.0).toDouble();
        _restoredCamera = true;
      });
    }
    gpsReady = await location.ensurePermission();
    if (mounted) setState(() {}); // native location puck once allowed
    // v6.4: lastKnown() itself now filters to a ≤3-minute-old fix — the
    // device-wide cache («то на речке, то в центре города») is rejected.
    // A stale/denied boot NEVER moves the camera and NEVER saves a fix:
    // only real fixes land in the restore point (see _onFix).
    final last = gpsReady ? await location.lastKnown() : null;
    if (last != null) {
      if (!_restoredCamera) {
        setState(() {
          lat = last.latitude;
          lon = last.longitude;
        });
      }
      _hasRealFix = true;
      if (mounted) setState(() {});
    }
    location.listen(_onFix);
    // v6.4: the «крутится когда ищет» spinner must not spin forever on a
    // device with no fix in sight — it stops after 20 s either way.
    Timer(const Duration(seconds: 20), () {
      if (mounted && !_hasRealFix && _locating) {
        setState(() => _locating = false);
      }
    });
    // v5.9: the phone compass — while NOT navigating the location arrow
    // follows the device heading so the user always sees which way they
    // face. Silent no-op on devices without a magnetometer.
    _listenCompass();
    voice = NavVoice();
    voice!.mode = state.voiceEngine;
    await voice!.init(state.locale);
    // v6.2: the sound toggle actually rules the speaker now.
    voice!.enabled = state.voiceOn;
    NavVoice.I = voice; // settings «Проверить голос» uses the same engine
    // Home / work / favorites must appear on the map — and re-appear the
    // moment the user saves or removes one.
    _boundState = state;
    state.addListener(_syncFavorites);
    // v6.8: switching the interface language or the speaker (system ↔
    // downloaded offline voice) must reach the live engine, not wait for a
    // restart — that is how a phone without Google speech services keeps
    // talking after the user picks a voice in settings.
    state.addListener(_syncVoice);
    _syncFavorites();
    _voiceSig = '${state.locale.languageCode}|${state.voiceEngine}';
    // v5.8: load the speed-camera cache and keep it fresh — the app gets
    // its documents dir injected first.
    try {
      final dir = await getApplicationDocumentsDirectory();
      CameraService.documentsDir = dir.path;
    } catch (_) {}
    await cameras.loadCache();
    // v6.1: bound the photo disk cache (the place-card pipeline) once.
    // ignore: discarded_futures
    PhotoCache.I.prune();
    // v5.8: auto-night check right at boot + every 5 minutes.
    _checkAutoNight(state);
    _autoNightTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _checkAutoNight(context.read<AppState>());
    });
    // Forest + the ten v5.2 premium recolors + the v5.3 satellite hybrid:
    // build the tinted documents up-front (one Liberty fetch total) so
    // switching themes is instant and the probe below can probe the ready
    // inline document.
    await ensureForestStyle();
    await ensureAllPremiumStyles();
    await ensureSatelliteStyle();
    // v6.4: Classic/Bright run the processed documents (cartography fix
    // + uncapped buildings) — all share the one cached Liberty fetch, so
    // this is instant after the first success. v6.5: Atlas/Onyx need NO
    // boot work at all — their documents are inline constants. v6.6: the
    // premium render family is synchronous too — every palette repaints
    // the inline Apple document on first request, nothing to warm up.
    await ensureClassicStyle();
    await ensureBrightStyle();
    // v5 pre-flight: a dead or very slow network is detected in ≤6 s and the
    // basemap starts directly in simplified raster mode — no 12 s boot stare.
    if (!await engine.probePrimary(state) && mounted) {
      setState(() => _useFallback = true);
      await engine.prepareLayers(state, fallback: true);
    } else if (mounted &&
        styleDocInlineFor(state.renderedStyle, state.premiumRender)) {
      setState(() {}); // rebuild → widget picks up the inline recolored doc
    }
    if (!gpsReady && mounted) {
      setState(() => _locating = false); // nothing to search without GPS
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('enableGps')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── v5.9: the compass feed ─────────────────────────────────────────────
  void _listenCompass() {
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSub = events.listen((event) {
      final h = event.heading;
      if (h == null || h.isNaN || !mounted) return;
      final state = context.read<AppState>();
      state.deviceHeading = h;
      // During guidance the GPS course drives the arrow; the compass only
      // rules in the idle mode. And the classic dot has nothing to rotate.
      final navActive =
          state.navPhase == NavPhase.navigating ||
          state.navPhase == NavPhase.rerouting;
      if (navActive || state.puckKind == PuckKind.dot) return;
      final prev = _lastAppliedHeading;
      // v6: ≥1.2° turn (with the 0/360 wrap handled) → repaint the arrow.
      // The 3° gate felt «медленно, с запазданием» — the plugin delivers
      // ~30 Hz, so a tight threshold keeps the rotation live and smooth.
      var delta = (h - (prev ?? h + 999)).abs();
      if (delta > 180) delta = 360 - delta;
      if (delta < 1.2) return;
      _lastAppliedHeading = h;
      _syncPuck(state);
    });
  }

  // ── v5.6: the moving marker (стрелка / машина / велосипед / человек) ───
  // Applied on every GPS fix and on every settings change; a signature
  // keeps redundant platform-channel calls away.
  // v5.9: in the IDLE mode the bearing comes from the device compass, so
  // the arrow spins N/W/S/E as the user turns the phone in place.
  String _puckSig = '';

  void _syncPuck(AppState state) {
    final kind = state.puckKind;
    // v6.4: the custom puck needs a REAL fix — a stale cache point must
    // never draw «я» somewhere the user has never been.
    final custom = kind != PuckKind.dot && gpsReady && _hasRealFix;
    final navActive =
        state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting;
    final dev = state.deviceHeading;
    final bearing = (custom && !navActive && dev != null) ? dev : heading;
    final sig = '$kind|$custom|$lat,$lon,$bearing';
    if (sig == _puckSig) return;
    _puckSig = sig;
    engine.setPuck(
      shown: custom,
      kind: kind,
      lat: lat,
      lon: lon,
      bearing: bearing,
    );
  }

  void _onFix(double la, double lo, double? hd, double speed) {
    if (!mounted) return;
    final firstFix = !_didInitialCenter;
    setState(() {
      lat = la;
      lon = lo;
      // v6.4: a real fix arrived — «я» больше не может быть рандомным, и
      // кнопка поиска перестаёт крутиться ровно в этот момент.
      _hasRealFix = true;
      _locating = false;
      // A fix without a usable course (standing still / cold sensor) keeps
      // the last bearing — the marker must not spin to 0.
      if (hd != null &&
          !hd.isNaN &&
          (speed == 0 || speed > 0.8 || heading == 0)) {
        heading = hd;
      }
    });
    // v5.4: persist the last real fix (throttled to one write per 5 s).
    _gpsSaveDebounce ??= Timer(const Duration(seconds: 5), () {
      _gpsSaveDebounce = null;
      context.read<AppState>().saveGpsFix(la, lo);
    });
    final state = context.read<AppState>();
    // v5.8: live speed for the HUD speedometer.
    state.speedKmh = (speed.isNaN ? 0 : speed) * 3.6;
    // v5.9: the compact sheet's maneuver line (street + distance to turn).
    final step = nav?.currentStep;
    if (step != null) {
      state.maneuverStreet = step.name;
      state.maneuverDistanceM = distanceM(la, lo, step.lat, step.lon);
    }
    _syncPuck(state);
    if (state.navPhase == NavPhase.navigating &&
        nav != null &&
        !state.isTransit) {
      nav!.onLocation(la, lo, speed);
      // v5.7 CAMERA FIX (the user: «когда я запустил маршрут я начал
      // скролить экран и смотреть его, но меня постоянно экран возвращает
      // к местоположению — убери этот лаг»): the camera only follows when
      // the user has not taken it over. Any manual pan/zoom unsets
      // [followMe] (see onCameraMove); the round recenter button resumes.
      if (followMe) {
        _followDebounce ??= Timer(const Duration(milliseconds: 900), () {
          _followDebounce = null;
          if (!mounted) return;
          final st = context.read<AppState>();
          if (st.navPhase == NavPhase.navigating && followMe && nav != null) {
            _moveProgrammatic(() => engine.navFollow(lat, lon, heading));
          }
        });
      }
      // v5.8 DRIVING ASSIST: the speed limit of the road ahead + camera
      // alerts. Both engines are fed the REMAINING route, are internally
      // throttled and fail silent — the HUD just never shows what OSM
      // does not know.
      final ahead = remainingAfter(la, lo, state.routeLine);
      limits.update(la, lo, ahead);
      final lim = limits.lastLimit;
      final limChanged = lim != state.speedLimitKmh;
      state.speedLimitKmh = lim;
      state.speedLimitAt = limits.lastChangedAt;
      CamAlert? alert;
      var camChanged = false;
      if (state.camWarnOn) {
        alert = cameras.feed(
          la,
          lo,
          ahead: ahead,
          courseDeg: heading,
          speedMps: speed.isNaN ? 0 : speed,
        );
        camChanged = (alert?.cam.key ?? '') != (state.camAlert?.cam.key ?? '');
        state.camAlert = alert;
        if (alert != null) {
          if (alert.justAnnounced && camChanged) {
            // Stage 1 — approach window: TTS + haptic + HUD chip.
            voice?.speak(
              '${S.of('camAhead')} · ${state.formatDistance(alert.distanceM)}'
              '${alert.cam.maxspeed != null ? ' · ${alert.cam.maxspeed}' : ''}',
            );
            if (state.hapticsOn) HapticFeedback.mediumImpact();
          } else if (alert.close && state.hapticsOn) {
            // Stage 2 — 150 m: heavy haptic (no TTS — never shout twice).
            HapticFeedback.heavyImpact();
          }
        }
      } else if (state.camAlert != null) {
        state.camAlert = null;
      }
      // One controlled repaint when driving-assist data actually moved
      // (updateProgress above already repaints the HUD itself).
      if (limChanged || camChanged) state.pulseAssist();
    } else if (state.navPhase == NavPhase.navigating &&
        state.isTransit &&
        transitRide != null) {
      // v5.7: transit follow — leg tracking by GPS + schedule.
      transitRide!.onLocation(la, lo);
    } else if (firstFix && !_restoredCamera) {
      // v5.1/v5.4: center ONCE on the first fix — and ONLY when there was
      // no restored camera (a restored session NEVER yanks the camera:
      // the app must reopen exactly where the user left it).
      _didInitialCenter = true;
      setState(() => followMe = true);
      _checkAutoNight(state);
      _moveProgrammatic(() => engine.moveTo(ml.LatLng(la, lo)));
    }
  }

  // ── v5.4: camera persistence ─────────────────────────────────────────
  void _onCameraIdlePersist() {
    // Called on every camera idle (pan/zoom/rotate settled). Debounced to
    // one prefs write per 1.5 s of stillness.
    _camSaveDebounce?.cancel();
    _camSaveDebounce = Timer(
      const Duration(milliseconds: 1500),
      _persistCameraNow,
    );
  }

  void _persistCameraNow() {
    _camSaveDebounce?.cancel();
    _camSaveDebounce = null;
    final pos = engine.cameraPosition;
    if (pos == null) return;
    if (!mounted) return;
    context.read<AppState>().saveCamera(
      LuxCam(
        lat: pos.target.latitude,
        lon: pos.target.longitude,
        zoom: pos.zoom,
        bearing: pos.bearing,
        tilt: pos.tilt,
      ),
    );
  }

  // ── Home / work / favorites on the map ────────────────────────────────
  // Cheap enough to run on EVERY AppState notification (navigation fires
  // them every second): a signature check turns it into a no-op unless the
  // saved places actually changed.
  String _favSig = '';

  void _syncFavorites() {
    final state = _boundState;
    if (state == null) return;
    final pts = <List<double>>[];
    final ics = <String>[];
    final h = state.home;
    final w = state.work;
    if (h != null) {
      pts.add([h.lat, h.lon]);
      ics.add('lux-home');
    }
    if (w != null) {
      pts.add([w.lat, w.lon]);
      ics.add('lux-work');
    }
    for (final f in state.favorites) {
      pts.add([f.lat, f.lon]);
      // v5.8: the pin keeps the color the user picked (6-color palette).
      ics.add('lux-fav-${f.colorIdx.clamp(0, kFavPinColors.length - 1)}');
    }
    final sig = '$pts|$ics';
    if (sig == _favSig) return;
    _favSig = sig;
    engine.setFavorites(points: pts, icons: ics);
  }

  /// v6.8: the language / speaker choice must reach the live voice without a
  /// restart — a microG phone has no system engine to fall back on, so the
  /// moment the user downloads a voice it has to start talking.
  String _voiceSig = '';

  void _syncVoice() {
    final state = _boundState;
    final v = voice;
    if (state == null || v == null) return;
    final sig = '${state.locale.languageCode}|${state.voiceEngine}';
    if (sig == _voiceSig) return;
    _voiceSig = sig;
    v
      ..setLocale(state.locale)
      ..mode = state.voiceEngine;
    // ignore: discarded_futures
    v.pickVoice();
  }

  // ── Routing ─────────────────────────────────────────────────────────────
  /// v5.3: routes from ANY start. [from] == null → start at the device
  /// location (the classic flow). An explicit start makes the full
  /// «Откуда → Куда» planner work; turn-by-turn remains available only
  /// when the start actually is the device location.
  ///
  /// v5.5: fetches ALL variants (fastest / shorter / toll-free…) and shows
  /// them as chips in the preview; roadworks along the line are probed
  /// asynchronously afterwards.
  Future<void> routeFromTo(
    LuxPlace? from,
    LuxPlace to, {
    List<LuxPlace> stops = const [],
  }) async {
    final state = context.read<AppState>();
    // v5.7: the TRANSIT profile rides Transitous (official GTFS feeds —
    // metro / RER / tram / bus), not the road routers.
    if (state.isTransit) {
      await _planTransit(from, to);
      return;
    }
    final fLat = from?.lat ?? lat;
    final fLon = from?.lon ?? lon;
    state.setDestination(to);
    state.routeStops = stops;
    state.beginRouting();
    try {
      final list = await routes.fetchRoutes(
        mode: state.mode,
        fromLat: fLat,
        fromLon: fLon,
        toLat: to.lat,
        toLon: to.lon,
        via: stops,
        options: RouteOptions(
          avoidTolls: state.avoidTolls,
          avoidMotorways: state.avoidMotorways,
          avoidFerries: state.avoidFerries,
        ),
      );
      // Label the variants: index 0 is the fastest; the shortest one (when
      // it is a DIFFERENT line) gets its own chip.
      var shortestIdx = 0;
      for (var i = 1; i < list.length; i++) {
        if (list[i].meters < list[shortestIdx].meters - 40) shortestIdx = i;
      }
      final alts = <RouteAlt>[
        for (var i = 0; i < list.length; i++)
          RouteAlt(
            meters: list[i].meters,
            seconds: list[i].seconds,
            line: list[i].line,
            label: i == 0 ? 'fast' : (i == shortestIdx ? 'short' : null),
            hasToll: list[i].hasToll,
            hasHighway: list[i].hasHighway,
            hasFerry: list[i].hasFerry,
          ),
      ];
      final preferred = state.routePref == RoutePref.short ? shortestIdx : 0;
      final r = list[preferred];
      state.showPreview(
        meters: r.meters,
        seconds: r.seconds,
        line: r.line,
        origin: from,
        alts: alts,
        preferredAlt: preferred,
      );
      await engine.drawRoute(r.line);
      await engine.drawTransit(null); // a road route replaces transit legs
      await engine.setPins(
        points: [
          [fLat, fLon],
          [to.lat, to.lon],
        ],
        icons: ['lux-pin-start', 'lux-pin-finish'],
      );
      await engine.fitLine(r.line);
      await engine.clearSelection();
      _probeIncidents(r.line);
      // v5.8: the destination lands in the history (recents) + cameras
      // along the WHOLE route are prefetched (cached on the device).
      // ignore: unawaited_futures
      state.addRecent(to);
      _prefetchCameras(<List<List<double>>>[
        r.line,
        for (final s in stops)
          <List<double>>[
            <double>[s.lat, s.lon],
          ],
      ]);
    } catch (e) {
      state.failRouting('${S.of('routeFailed')} — ${S.of('checkNet')}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('routeFailed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// v5.5: switch the displayed variant (chips in the preview card).
  Future<void> _pickAlt(int i) async {
    final state = context.read<AppState>();
    final a = state.selectAlt(i);
    if (a == null) return;
    final start = state.routeOrigin;
    await engine.drawRoute(a.line);
    await engine.setPins(
      points: [
        [start?.lat ?? lat, start?.lon ?? lon],
        [state.destination!.lat, state.destination!.lon],
      ],
      icons: ['lux-pin-start', 'lux-pin-finish'],
    );
    await engine.fitLine(a.line);
    _probeIncidents(a.line);
  }

  /// v5.5: roadworks / closures along the route — asynchronous, never
  /// blocks the route; late answers from a previous route are discarded.
  Future<void> _probeIncidents(List<List<double>> line) async {
    final state = context.read<AppState>();
    if (state.navPhase != NavPhase.preview) return;
    final token = ++_incidentToken;
    state.setIncidentsChecking(); // «проверяем…»
    try {
      final found = await incidents.fetchAlong(line);
      if (!mounted || token != _incidentToken) return;
      final st = context.read<AppState>();
      if (st.navPhase != NavPhase.preview) return;
      st.setIncidentsFound(found.length);
      _lastIncidentPts = [
        for (final i in found) [i.lat, i.lon],
      ];
      await engine.setIncidents(_lastIncidentPts);
    } catch (_) {
      if (!mounted || token != _incidentToken) return;
      final st = context.read<AppState>();
      if (st.navPhase == NavPhase.preview) {
        st.setIncidentsFound(0);
      }
    }
  }

  Future<void> routeTo(LuxPlace dest) => routeFromTo(null, dest);

  /// v5.8: cameras along the route — bbox of all points + 3 km halo,
  /// fetched once per route and cached on the device by [CameraService].
  Future<void> _prefetchCameras(List<List<List<double>>> shapes) async {
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final shape in shapes) {
      for (final p in shape) {
        if (p[0] < minLat) minLat = p[0];
        if (p[0] > maxLat) maxLat = p[0];
        if (p[1] < minLon) minLon = p[1];
        if (p[1] > maxLon) maxLon = p[1];
      }
    }
    minLat -= 0.027;
    maxLat += 0.027;
    minLon -= 0.027;
    maxLon += 0.027;
    cameras.resetAlerts();
    await cameras.ensureArea(minLat, minLon, maxLat, maxLon);
    if (!mounted) return;
    await engine.setCameras([
      for (final c in cameras.cams) [c.lat, c.lon],
    ]);
  }

  // ── v5.8: AUTO-NIGHT (карта темнеет по закату) ───────────────────────
  /// v6.7: the catalog is the single source of truth for «is this theme
  /// dark». The old hand-kept list was never told about the v6.5 themes, so
  /// Оникс counted as LIGHT and AUTO-NIGHT repainted it Нуар in the evening.
  static bool _isDarkStyle(MapStyle s) => mapStyleInfo(s)?.dark ?? false;

  void _checkAutoNight(AppState state) {
    if (!state.autoNightOn || lat == 48.8566 && lon == 2.3522) {
      // No GPS yet (or the fresh-install Paris default) — do not fight the
      // user's theme with a made-up position.
      return;
    }
    // Never fight the raster modes — Спутник / Рельеф are explicit.
    if (state.mapStyle == MapStyle.satellite ||
        state.mapStyle == MapStyle.relief) {
      state.setNightShade(false);
      return;
    }
    // v6.7: only LIGHT themes get the shade, and only for the duration of
    // the night — the saved choice stays exactly where the user left it.
    state.setNightShade(
      isNightNow(lat, lon) && !_isDarkStyle(state.mapStyle),
    );
  }

  // ── v5.7: PUBLIC TRANSPORT (Transitous) ──────────────────────────────
  Future<void> _planTransit(LuxPlace? from, LuxPlace to) async {
    final state = context.read<AppState>();
    final fLat = from?.lat ?? lat;
    final fLon = from?.lon ?? lon;
    state.setDestination(to);
    state.beginRouting();
    try {
      final list = await transit.plan(
        fromLat: fLat,
        fromLon: fLon,
        toLat: to.lat,
        toLon: to.lon,
      );
      if (!mounted) return;
      state.showTransitOptions(list);
      final plan = state.transitPlan;
      if (plan == null) {
        state.failRouting(S.of('transitFail'));
        return;
      }
      await engine.drawRoute(null); // a transit plan replaces road lines
      await engine.drawTraveled(const []);
      await engine.drawTransit([
        for (final leg in plan.legs)
          TransitLineLeg(leg.points, walk: leg.isWalk, color: leg.color),
      ]);
      await engine.setPins(points: []);
      await engine.setIncidents(const []);
      await engine.fitLine(
        [for (final leg in plan.legs) ...leg.points],
        top: 120,
        bottom: 300,
      );
      await engine.clearSelection();
    } catch (_) {
      state.failRouting('${S.of('transitFail')} — ${S.of('checkNet')}');
    }
  }

  /// Switch the drawn departure option (chips in the preview card).
  Future<void> _pickTransitPlan(int i) async {
    final state = context.read<AppState>();
    final plan = state.selectTransitPlan(i);
    if (plan == null) return;
    await engine.drawTransit([
      for (final leg in plan.legs)
        TransitLineLeg(leg.points, walk: leg.isWalk, color: leg.color),
    ]);
    await engine.fitLine(
      [for (final leg in plan.legs) ...leg.points],
      top: 120,
      bottom: 300,
    );
  }

  /// Starts riding the chosen itinerary: HUD + notifications + TTS.
  Future<void> _startTransitRide() async {
    final state = context.read<AppState>();
    final plan = state.transitPlan;
    if (plan == null) return;
    NavNotifications.requestPermissions();
    NavNotifications.keepScreenOn(true);
    transitRide = TransitSession(
      plan,
      TransitCallbacks(
        onLegChanged: (i) {
          final st = context.read<AppState>();
          if (st.navPhase != NavPhase.navigating) return;
          st.advanceTransitLeg(i);
          final leg =
              st.transitPlan?.legs[i.clamp(0, st.transitPlan!.legs.length - 1)];
          if (leg == null) return;
          _speakLeg(leg);
          _updateTransitNotification(st, leg);
        },
        onApproachExit: (stopName) {
          final st = context.read<AppState>();
          if (st.navPhase != NavPhase.navigating) return;
          voice?.speak("${S.of('exitAt')} «$stopName»");
        },
        onProgress: (remainM, legIndex) {
          final st = context.read<AppState>();
          if (st.navPhase != NavPhase.navigating) return;
          st.transitStopM = remainM;
          // The HUD re-renders on the ticker; no notifyListeners storm.
        },
        onArrive: () {
          final st = context.read<AppState>();
          if (st.navPhase == NavPhase.arrived) return;
          st.arrive();
          voice?.speak(S.of('arrived'));
          NavNotifications.update(
            title: S.of('arrived'),
            text: st.destination?.name ?? '',
          );
        },
      ),
    );
    state.startTransit();
    transitRide!.start();
    _navOverview = false;
    setState(() => followMe = true);
    engine.navFollow(lat, lon, 0);
    // Announce + notify the first leg immediately.
    final first = plan.legs.first;
    _speakLeg(first);
    _updateTransitNotification(state, first);
  }

  void _speakLeg(TransitLeg leg) {
    if (leg.isWalk) {
      voice?.speak("${S.of('inWalk')} ${S.of('untilStop')} «${leg.toName}»");
    } else {
      final to = leg.headsign.isNotEmpty ? leg.headsign : leg.toName;
      voice?.speak("${S.of('boardAt')} ${leg.line} ${S.of('untilStop')} «$to»");
    }
  }

  void _updateTransitNotification(AppState state, TransitLeg leg) {
    final title = leg.isWalk
        ? "${S.of('inWalk')}: ${S.of('walkTo')} «${leg.toName}»"
        : "${leg.line} → ${leg.headsign.isNotEmpty ? leg.headsign : leg.toName}";
    final text =
        "${S.of('exitAt')} «${leg.toName}» · ${state.formatDuration(state.transitPlan!.durationSec.toDouble())}";
    final sig = '$title|$text';
    if (sig == _notifSig) return;
    _notifSig = sig;
    NavNotifications.update(title: title, text: text);
  }

  Future<void> _rebuildForMode() async {
    final state = context.read<AppState>();
    final dest = state.destination;
    if (dest == null) return;
    if (state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting) {
      return;
    }
    await routeFromTo(state.routeOrigin, dest);
  }

  /// True when the drawn route starts at (or very near) the device — only
  /// then can turn-by-turn guidance drive progress. An explicit planner
  /// start elsewhere gives a preview-only route.
  bool _originIsDevice(AppState state) {
    final o = state.routeOrigin;
    if (o == null) return true;
    return distanceM(o.lat, o.lon, lat, lon) < 150;
  }

  Future<void> _startNavigation() async {
    final state = context.read<AppState>();
    if (state.routeLine.length < 2 || state.destination == null) return;
    if (!_originIsDevice(state)) return; // preview-only route
    // v5.1: a failed re-fetch here used to crash the flow and leave the
    // user stuck on the preview — navigation must either start or show WHY.
    final LuxRoute r;
    try {
      r = await routes.fetchRoute(
        mode: state.mode,
        fromLat: lat,
        fromLon: lon,
        toLat: state.destination!.lat,
        toLon: state.destination!.lon,
        via: state.routeStops,
      );
    } catch (_) {
      state.failRouting('${S.of('routeFailed')} — ${S.of('checkNet')}');
      return;
    }
    state.showPreview(
      meters: r.meters,
      seconds: r.seconds,
      line: r.line,
      origin: null, // guidance always starts from the device
    );
    await engine.drawRoute(r.line);
    nav = NavSession(
      r,
      state.mode,
      NavCallbacks(
        onProgress: (m, s, traveled) {
          final st = context.read<AppState>();
          st.currentManeuver = nav?.currentStep?.key ?? 'straight';
          st.updateProgress(m, s, traveled);
          engine.drawTraveled(traveled);
          _updateCarNotification(st);
        },
        onAnnounce: (key) {
          final street = nav?.currentStep?.name ?? '';
          final sentence = voice!.localize(key, street);
          voice?.speak(sentence);
          // v5.8: tactile feedback rides along with every spoken turn.
          if (context.read<AppState>().hapticsOn) {
            HapticFeedback.mediumImpact();
          }
          // v5.7: the PREMIUM PUSH — heads-up, lock-screen, updated with
          // every maneuver («пуш уведомления красивые чтобы знать куда
          // ехать пуш на заблокированном»).
          final st = context.read<AppState>();
          _notifSig = '$key|$street';
          NavNotifications.update(
            title: sentence,
            text:
                "${S.of('eta')}: ${st.formatDuration(st.remainingSeconds)} · ${st.formatDistance(st.remainingMeters)}",
          );
        },
        onReroute: () async {
          final st = context.read<AppState>();
          if (st.navPhase != NavPhase.navigating) return;
          st.rerouting();
          try {
            final rr = await routes.reroute(
              mode: st.mode,
              lat: lat,
              lon: lon,
              toLat: st.destination!.lat,
              toLon: st.destination!.lon,
            );
            st.showPreview(
              meters: rr.meters,
              seconds: rr.seconds,
              line: rr.line,
            );
            st.startNavigating();
            await engine.drawRoute(rr.line);
          } catch (_) {
            st.backToPreview();
          }
        },
        onArrive: () {
          final st = context.read<AppState>();
          if (st.navPhase == NavPhase.arrived) return;
          st.arrive();
          voice?.speak(S.of('arrived'));
          if (st.hapticsOn) HapticFeedback.heavyImpact();
          NavNotifications.update(
            title: S.of('arrived'),
            text: st.destination?.name ?? '',
          );
          engine.zoomTo(16.4);
        },
      ),
      offRouteM: state.mode == TravelMode.foot ? 30 : 48,
    );
    state.startNavigating();
    // v5.7: LOCKED-SCREEN NAVIGATION — foreground service + notification,
    // runtime permissions, screen stays awake while the HUD is up.
    NavNotifications.requestPermissions();
    NavNotifications.keepScreenOn(true);
    _navOverview = false;
    _notifSig = '';
    setState(() => followMe = true); // follow until the user takes over
    await engine.setPins(
      points: [
        [state.destination!.lat, state.destination!.lon],
      ],
      icons: ['lux-pin-finish'],
    );
    await _moveProgrammatic(() => engine.navFollow(lat, lon, heading));
    // First notification right away — the user sees the guidance is alive.
    _updateCarNotification(state);
  }

  /// v5.7: car navigation notification — the next maneuver + live ETA.
  /// v5.8: an active camera warning rides in the text as well.
  void _updateCarNotification(AppState state) {
    final key = nav?.currentStep?.key ?? 'straight';
    final street = nav?.currentStep?.name ?? '';
    final cam = state.camAlert;
    final sig = 'prog|$key|$street|${cam?.cam.key}';
    if (sig == _notifSig && _notifThrottle?.isActive != true) return;
    _notifSig = sig;
    _notifThrottle?.cancel();
    _notifThrottle = Timer(const Duration(milliseconds: 2500), () {});
    final sentence = voice?.localize(key, street) ?? street;
    NavNotifications.update(
      title: sentence,
      text:
          "${S.of('eta')}: ${state.formatDuration(state.remainingSeconds)} · ${state.formatDistance(state.remainingMeters)}"
          '${cam != null ? ' · ${S.of('camChip')} ${state.formatDistance(cam.distanceM)}' : ''}',
    );
  }

  /// v5.7: route overview while navigating — zoom out to the whole route
  /// («нужен маршрут отдельно чтобы посмотреть»); press again / recenter to
  /// return to the follow camera.
  void _toggleOverview() {
    final state = context.read<AppState>();
    if (_navOverview) {
      setState(() {
        _navOverview = false;
        followMe = true;
      });
      _moveProgrammatic(() => engine.navFollow(lat, lon, heading));
    } else {
      setState(() => _navOverview = true);
      final line = state.routeLine;
      if (line.length >= 2) {
        _moveProgrammatic(() => engine.fitLine(line, top: 150, bottom: 280));
      }
    }
  }

  Future<void> _stopNavigation() async {
    final state = context.read<AppState>();
    nav?.dispose();
    nav = null;
    transitRide?.dispose();
    transitRide = null;
    _navOverview = false;
    limits.lastLimit = null;
    cameras.resetAlerts();
    state.resetRoute();
    // v5.7: the guidance is over — kill the notification + FGS + wakelock.
    NavNotifications.stop();
    NavNotifications.keepScreenOn(false);
    await engine.drawRoute(null);
    await engine.drawTraveled(const []);
    await engine.drawTransit(null);
    await engine.setPins(points: []);
    await engine.setCameras(const []);
    _didInitialCenter = true; // do not yank the camera on the next fix
    _moveProgrammatic(() => engine.moveTo(ml.LatLng(lat, lon), zoom: 14.5));
  }

  // ── Map gestures ────────────────────────────────────────────────────
  /// v6.2 THE TAP-DEADLOCK FIX («тапаю по местам раз 10 … тап уже не
  /// открывал меню нигде … я ждал минуту и окно после долгой паузы само
  /// открылось как будто таймаут был тапов»): the old flow awaited
  /// Nominatim reverse / OSM tags BEFORE showing the sheet, holding
  /// _sheetBusy — a throttled request blocked EVERY tap for up to a
  /// minute. Now the sheet opens INSTANTLY on local tile data and the
  /// network lands progressively INSIDE the card. _sheetBusy only covers
  /// the millisecond platform-channel picks.
  Future<void> _onMapTap(math.Point<double> point, ml.LatLng coords) async {
    final state = context.read<AppState>();
    if (state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting) {
      return;
    }
    // v5.5: a sheet is opening or open — ignore the tap (the user's
    // duplicate-window bug: two fast taps pushed two identical sheets).
    if (_sheetBusy || luxSheetOpen) return;
    _sheetBusy = true;
    try {
      final picked = await engine.pickPoi(
        Offset(point.x.toDouble(), point.y.toDouble()),
        coords.latitude,
        coords.longitude,
      );
      if (picked != null && picked.name.isNotEmpty) {
        await engine.clearBuildingHighlight();
        await engine.showSelection(picked.lat, picked.lon);
        if (!mounted) return;
        _sheetBusy = false; // from here the sheet guard is luxSheetOpen
        await showPlaceSheet(
          context,
          LuxPlace(
            name: picked.name,
            subtitle: picked.category,
            lat: picked.lat,
            lon: picked.lon,
            kind: 'poi',
          ),
          onRoute: routeTo,
          onPlan: (p) => _openPlanner(to: p),
        );
        return;
      }
      // v5.9: BUILDING PICK — «Добавь здания не 3d а обычные чтобы я сам
      // выбрал на карте какие будут!» The footprint lights up in the
      // accent + the card resolves the real OSM tags (этажи, высота)
      // progressively — v6.2: WITHOUT waiting for the network.
      final zoom = engine.cameraPosition?.zoom ?? 0;
      if (zoom >= 15) {
        final b = await engine.pickBuilding(
          Offset(point.x.toDouble(), point.y.toDouble()),
          coords.latitude,
          coords.longitude,
        );
        if (b != null) {
          final cLat = b.centroidLat;
          final cLon = b.centroidLon;
          await engine.showSelection(cLat, cLon);
          await engine.highlightBuilding(b.ring);
          if (!mounted) return;
          _sheetBusy = false;
          await showPlaceSheet(
            context,
            LuxPlace(
              name: b.name ?? '',
              subtitle: '',
              lat: cLat,
              lon: cLon,
              kind: 'building',
            ),
            onRoute: routeTo,
            onPlan: (p) => _openPlanner(to: p),
            building: BuildingInfo(heightM: b.heightM),
          );
          return;
        }
      }
      // v6.2: empty tap → the pin card opens NOW («Выбранная точка» +
      // coordinates); the address arrives via the progressive Nominatim
      // details inside the card.
      await engine.clearBuildingHighlight();
      await engine.showSelection(coords.latitude, coords.longitude);
      if (!mounted) return;
      _sheetBusy = false;
      await showPlaceSheet(
        context,
        LuxPlace(
          name: S.of('droppedPin'),
          subtitle:
              '${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}',
          lat: coords.latitude,
          lon: coords.longitude,
          kind: 'pin',
        ),
        onRoute: routeTo,
        onPlan: (p) => _openPlanner(to: p),
      );
    } finally {
      _sheetBusy = false;
    }
  }

  /// v5.8: LONG-PRESS map menu — quick power actions («долгое нажатие на
  /// карте → контекстное меню»). Same guard family as the single tap; the
  /// menu itself is a tagged lux sheet.
  Future<void> _onMapLongPress(
    math.Point<double> point,
    ml.LatLng coords,
  ) async {
    final state = context.read<AppState>();
    if (state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting) {
      return;
    }
    if (_sheetBusy || luxSheetOpen) return;
    _sheetBusy = true;
    try {
      await engine.showSelection(coords.latitude, coords.longitude);
      LuxPlace place;
      try {
        // v6.2: the menu must never hang the tap guard — 4 s cap (the old
        // 12 s wait on a throttled Nominatim was exactly the «тап мёртв
        // минуту» report).
        place = await geocoding
            .reverse(coords.latitude, coords.longitude)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        place = LuxPlace(
          name: S.of('droppedPin'),
          subtitle:
              '${coords.latitude.toStringAsFixed(5)}, ${coords.longitude.toStringAsFixed(5)}',
          lat: coords.latitude,
          lon: coords.longitude,
        );
      }
      if (!mounted) return;
      await showLuxSheet(
        context: context,
        tag: 'mapmenu',
        scrollable: false,
        builder: (_) => _MapLongPressMenu(
          place: place,
          onRouteHere: () {
            Navigator.of(context).pop();
            routeTo(place);
          },
          onRouteFrom: () {
            Navigator.of(context).pop();
            _openPlanner(from: place);
          },
          onFavorite: () async {
            final st = context.read<AppState>();
            await st.toggleFavorite(place);
            if (!mounted) return;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of('savedTo')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onShare: () {
            Navigator.of(context).pop();
            NavNotifications.shareText(
              place.name,
              '${place.name}\n'
              'https://www.openstreetmap.org/?mlat=${place.lat}&mlon=${place.lon}#map=17/${place.lat}/${place.lon}',
            );
          },
        ),
      );
    } finally {
      _sheetBusy = false;
    }
  }

  // ── Style lifecycle ─────────────────────────────────────────────────────
  // The MaplibreMap widget reacts to a changed `styleString` natively; the
  // engine caches the document per signature and re-installs overlays in
  // onStyleLoaded.

  Future<void> _restoreOverlays(AppState state) async {
    if (state.destination == null) return;
    // v5.7: transit legs survive style reloads too.
    final plan = state.transitPlan;
    if (state.isTransit && plan != null) {
      await engine.drawTransit([
        for (final leg in plan.legs)
          TransitLineLeg(leg.points, walk: leg.isWalk, color: leg.color),
      ]);
      return;
    }
    // v6.1: speed cameras + roadworks survive the wake rebuild too.
    if (cameras.cams.isNotEmpty) {
      await engine.setCameras([
        for (final c in cameras.cams) [c.lat, c.lon],
      ]);
    }
    if (_lastIncidentPts.isNotEmpty) {
      await engine.setIncidents(_lastIncidentPts);
    }
    if (state.routeLine.length >= 2 &&
        (state.navPhase == NavPhase.preview ||
            state.navPhase == NavPhase.navigating ||
            state.navPhase == NavPhase.rerouting)) {
      await engine.drawRoute(state.routeLine);
      if (state.traveledLine.length >= 2) {
        await engine.drawTraveled(state.traveledLine);
      }
      await engine.setPins(
        points: [
          [state.destination!.lat, state.destination!.lon],
        ],
        icons: ['lux-pin-finish'],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.effectiveTheme;
    // v5.5/v5.9: apply the buildings MODE to the LIVE map the moment it
    // changes (Обычные / 3D / Выкл).
    if (_appliedBld != state.buildingsMode) {
      _appliedBld = state.buildingsMode;
      // ignore: unawaited_futures
      engine.applyBuildingsMode(state.buildingsMode);
    }
    // v6.6: the rendering family is part of the signature — switching
    // «Классика ↔ Премиум Atlas» hot-swaps the document like a theme does.
    // v6.8: but ONLY when the family really swaps the document (Шёлк/Оникс/
    // Спутник draw the same style either way), otherwise the map waits for a
    // reload that never comes and the watchdog drops it into raster mode.
    final fam =
        state.premiumRender && familyMattersFor(state.renderedStyle);
    final styleSig =
        '${state.renderedStyle.name}|${fam ? 1 : 0}|$_useFallback|${styleDocInlineFor(state.renderedStyle, state.premiumRender)}';
    _ensureWatchdog(styleSig, fallback: _useFallback);
    _syncPuck(state);
    final waiting = _loadedSig != styleSig;
    // v6.5: a style change (theme switch / watchdog fallback) swaps the
    // native document — arm the cover for that swap. The reveal happens
    // in onStyleLoadedCallback. First build: the field defaults already
    // cover the map.
    if (_scrimSig != styleSig) {
      _scrimSig = styleSig;
      if (_everLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _coverMap();
        });
      }
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // v5.9: the guidance surfaces (car + transit) are the new full-width
    // bottom sheets; the top becomes the compact nav strip.
    final navSheet =
        state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting;
    // v5.4: the right button cluster sits above the panel when one is up.
    final panelUp =
        state.navPhase != NavPhase.idle || state.destination != null;
    final clusterBottom = (panelUp ? _panelBottom(state) : 18.0) + bottomInset;

    return Scaffold(
      // v5.5 CRITICAL (the user: «при тапе на панель поиска панель которая
      // снизу выезжает также поднимает карту и всё что снизу!!»): the
      // keyboard must NEVER resize the Scaffold — the map is a full-screen
      // body and shrank/rode up every time the search sheet autofocused.
      // resizeToAvoidBottomInset:false keeps the map FROZEN in place; the
      // sheets lift themselves above the keyboard via viewInsets padding.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          ml.MapLibreMap(
            // v6.1 WAKE FIX v2: the key bumps after every lock-screen wake —
            // Flutter then builds a FRESH native map view. The native
            // SurfaceView (the fast, hardware-composited path) is back for
            // good — no more TextureView scroll lag.
            key: ValueKey('lux-map-$_mapRev'),
            styleString: engine.styleJson(state, fallback: _useFallback),
            initialCameraPosition:
                _wakeCam ??
                ml.CameraPosition(target: ml.LatLng(lat, lon), zoom: zoom0),
            onMapCreated: (c) {
              engine.attach(c);
              engine.prepareLayers(state, fallback: _useFallback);
            },
            onStyleLoadedCallback: () async {
              // v5: sprites/overlays/3D are best-effort. If ANY of them
              // throws, the map ITSELF is still loaded — we must still
              // clear the boot screen, or the user stares at “Загружаем
              // карту…” over a perfectly working basemap (the v4 bug).
              try {
                await engine.onStyleLoaded(state);
                await _restoreOverlays(state);
                _syncFavorites();
              } catch (_) {}
              _markLoaded(styleSig);
            },
            myLocationEnabled:
                gpsReady && _hasRealFix && state.puckKind == PuckKind.dot,
            // v5.1: the native MapLibre location puck (blue dot with halo) —
            // shown when the user keeps the classic dot; v5.6 replaces it
            // with the chosen arrow / car / bike / person marker otherwise.
            myLocationRenderMode: ml.MyLocationRenderMode.normal,
            // v5: the native compass sits at the TOP-RIGHT corner (too high,
            // per user feedback) — replaced by an in-theme button in the
            // bottom-right control cluster.
            compassEnabled: false,
            // v6.1: NATIVE SurfaceView again (VirtualDisplay path). The
            // v6.0 TextureView wake fix made scrolling laggy («сролл карты
            // с тормозами… фризит!») — the wake bug is now cured by the
            // keyed rebuild (see _reviveMapAfterWake) instead.
            // v5: the “!” attribution button is pushed off-screen. Data
            // credits stay visible in Settings and in the boot screen copy.
            attributionButtonMargins: const math.Point(-200, -200),
            trackCameraPosition: true,
            rotateGesturesEnabled: true,
            onMapClick: _onMapTap,
            // v5.8: the long-press power menu (маршрут сюда / отсюда /
            // в избранное / поделиться).
            onMapLongClick: _onMapLongPress,
            // v5.4: remember the camera the moment the map settles — the
            // next launch opens exactly here, not in Paris.
            onCameraIdle: _onCameraIdlePersist,
            onCameraMove: (pos) {
              // v5.1: ANY camera movement that we did not start ourselves
              // is the user's finger — unpin the "follow me" state so the
              // recenter button honestly reflects reality.
              if (!_cameraProgrammatic && followMe && mounted) {
                setState(() => followMe = false);
              }
              // Only rebuild for a real rotation — onCameraMove fires on
              // every pan frame.
              if ((_bearing - pos.bearing).abs() > 1.2 && mounted) {
                setState(() => _bearing = pos.bearing);
              }
            },
          ),

          // v6.5 FADE-IN MASK: the map «проявляется» — the platform view's
          // blank creation frame, the style swap and the wake rebuild are
          // all covered by an opaque scrim in the theme's own land color,
          // which fades out after the style loads (see _revealMap).
          if (_scrimUp)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _scrimSolid ? 1 : 0,
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: _scrimColor(state)),
                  ),
                ),
              ),
            ),

          // First-launch boot screen while the hosted style loads.
          if (!_everLoaded && waiting && !_fatal)
            Positioned.fill(child: _MapBoot(theme: t)),

          // Subsequent style switches / fallback status chip.
          if (waiting && _everLoaded && !_fatal)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: _StatusChip(
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: S.of('mapUpdating'),
                  ),
                ),
              ),
            ),

          // v5.9 LAYOUT CONTRACT: the top has ONLY the search pill and
          // the settings button — EXCEPT during navigation, when the
          // search field shrinks into a small round button on the left
          // and the km + arrival info move up here («…укарачивалось в круг
          // маленький слево а туда перемещалось и км и инфа»).
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: navSheet
                  ? NavTopBar(
                      state: state,
                      onStop: _stopNavigation,
                      onOverview: _toggleOverview,
                      overviewActive: _navOverview,
                      onToggleSound: () {
                        final st = context.read<AppState>();
                        final on = !st.voiceOn;
                        // ignore: discarded_futures
                        st.setVoice(on);
                        // v6.2: the gate the speaker actually reads.
                        voice?.enabled = on;
                      },
                    )
                  : Row(
                      children: [
                        Expanded(child: _SearchPill(onTap: _openSearch)),
                        const SizedBox(width: 8),
                        RoundFab(
                          icon: Icons.tune_rounded,
                          tooltip: S.of('settings'),
                          onTap: _openSettings,
                        ),
                      ],
                    ),
            ),
          ),

          // Right control cluster (bottom-right): layers + favorites +
          // planner, then compass + recenter. Hidden while a bottom panel
          // owns the screen (preview / navigation) except the compass and
          // recenter, which stay useful there.
          Positioned(
            right: 12,
            bottom: clusterBottom,
            child: Column(
              children: [
                if (!panelUp) ...[
                  RoundFab(
                    icon: Icons.layers_rounded,
                    tooltip: S.of('layers'),
                    onTap: _openLayers,
                  ),
                  const SizedBox(height: 10),
                  RoundFab(
                    icon: Icons.star_rounded,
                    tooltip: S.of('favorites'),
                    onTap: _openSaved,
                  ),
                  const SizedBox(height: 10),
                  RoundFab(
                    icon: Icons.route_rounded,
                    tooltip: S.of('planRoute'),
                    onTap: () => _openPlanner(),
                  ),
                  const SizedBox(height: 10),
                ],
                RoundFab(
                  icon: Icons.explore_rounded,
                  tooltip: S.of('compass'),
                  active: _bearing.abs() > 2,
                  onTap: engine.resetNorth,
                  child: Transform.rotate(
                    angle: -_bearing * math.pi / 180,
                    child: Icon(
                      Icons.explore_rounded,
                      size: 22,
                      color: _bearing.abs() > 2 ? t.onPrimary : t.onBackground,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                RoundFab(
                  icon: followMe
                      ? Icons.gps_fixed_rounded
                      : Icons.gps_not_fixed_rounded,
                  tooltip: S.of('recenter'),
                  active: followMe && gpsReady,
                  // v6.4: «круг должен крутиться когда ищет» — the button
                  // spins during boot acquisition and while _locateMe works.
                  busy: _locating,
                  onTap: _locateMe,
                ),
              ],
            ),
          ),

          // v6: the scale — a ROUND badge in the circle language of every
          // other map control («она у тебя слева в прямоугольном макете со
          // шкалой занимает место сделай ее в круглую кнопку!»).
          if (!_fatal &&
              _everLoaded &&
              state.navPhase == NavPhase.idle &&
              state.destination == null)
            Positioned(
              left: 12,
              bottom: 240 + bottomInset,
              child: _ScaleBar(engine: engine),
            ),

          // Travel mode capsule (bottom-left, above the panel).
          if (state.navPhase == NavPhase.idle && state.destination == null)
            Positioned(
              left: 12,
              bottom: 18 + bottomInset,
              child: _ModeCapsule(
                mode: state.mode,
                onPick: (m) async {
                  state.setMode(m);
                  await _rebuildForMode();
                },
              ),
            ),

          // THE bottom panel. Lifted above the system gesture/navigation
          // bar (v5): edge-to-edge means the Scaffold extends under it, so
          // the raw `bottom: 10` put the panels BELOW the nav bar.
          // v5.9: while GUIDANCE runs the panel is a REAL bottom sheet —
          // full width, attached to the very bottom edge, nothing floating.
          Positioned(
            left: navSheet ? 0 : 10,
            right: navSheet ? 0 : 10,
            bottom: navSheet ? 0 : 10 + bottomInset,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.14),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _BottomPanel(
                key: ValueKey(
                  'panel-${state.navPhase.name}-${state.routeError ?? ''}-${state.isTransit}',
                ),
                state: state,
                canStart: _originIsDevice(state),
                onStart: _startNavigation,
                onStop: _stopNavigation,
                onRouteTo: routeTo,
                onPickAlt: _pickAlt,
                onTransitStart: _startTransitRide,
                onTransitPick: _pickTransitPlan,
                onOverview: _toggleOverview,
                overviewActive: _navOverview,
                onModeChanged: (m) async {
                  state.setMode(m);
                  await _rebuildForMode();
                },
                onClose: () {
                  state.resetRoute();
                  engine.drawRoute(null);
                  engine.drawTransit(null);
                  engine.setPins(points: []);
                  engine.setIncidents(const []);
                  engine.clearSelection();
                  _incidentToken++; // a pending lookup must not repaint
                },
              ),
            ),
          ),

          if (!gpsReady)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.outline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_off_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.of('lookingForYou'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Persistent notice: the map is running in simplified mode.
          if (_useFallback && !_fatal && !waiting)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: _StatusChip(
                    icon: Icon(Icons.bolt_rounded, size: 15, color: t.primary),
                    label: S.of('simpleBanner'),
                  ),
                ),
              ),
            ),

          // Fatal: neither the hosted style nor the raster fallback loaded.
          if (_fatal)
            Positioned.fill(
              child: _MapFatal(
                theme: t,
                onRetry: _retryMap,
                onSimple: _forceSimpleMode,
              ),
            ),
        ],
      ),
    );
  }

  /// The visible camera, as the search anchor when there is no GPS fix.
  LuxCam? _viewCam() {
    final pos = engine.cameraPosition;
    if (pos == null) return null;
    return LuxCam(
      lat: pos.target.latitude,
      lon: pos.target.longitude,
      zoom: pos.zoom,
    );
  }

  double _panelBottom(AppState state) {
    if (state.navPhase == NavPhase.idle && state.destination == null) {
      return 20;
    }
    // v5.9: the nav SHEET is slim (~118 px collapsed) — the cluster sits
    // just above it instead of above the old half-screen card.
    final nav =
        state.navPhase == NavPhase.navigating ||
        state.navPhase == NavPhase.rerouting;
    return nav ? 140 : 210;
  }

  /// v6.7: search is a real full-screen page on the stack (not a sheet over
  /// the map); the picked place flies the camera and opens the place card.
  Future<void> _openSearch() async {
    final picked = await openPlaceSearch(context, camera: _viewCam());
    if (picked == null || !mounted) return;
    await _moveProgrammatic(
      () => engine.moveTo(ml.LatLng(picked.lat, picked.lon), zoom: 15.8),
    );
    if (!mounted) return;
    await showPlaceSheet(
      context,
      picked,
      onRoute: routeTo,
      onPlan: (p) => _openPlanner(to: p),
    );
  }

  /// v5.3: the saved-places window (Избранное) — show / route / delete.
  Future<void> _openSaved() async {
    final pick = await showSavedSheet(context);
    if (pick == null || !mounted) return;
    if (pick.action == SavedAction.route) {
      await routeFromTo(null, pick.place);
      return;
    }
    await _moveProgrammatic(
      () =>
          engine.moveTo(ml.LatLng(pick.place.lat, pick.place.lon), zoom: 15.8),
    );
    if (!mounted) return;
    await showPlaceSheet(
      context,
      pick.place,
      onRoute: routeTo,
      onPlan: (p) => _openPlanner(to: p),
    );
  }

  /// v5.3: the «Откуда → Куда» planner with the endpoint swap.
  Future<void> _openPlanner({LuxPlace? to, LuxPlace? from}) async {
    final plan = await showRoutePlanner(context, from: from, to: to);
    if (plan == null || !mounted) return;
    await routeFromTo(plan.from, plan.to, stops: plan.stops);
  }

  Future<void> _openLayers() async {
    await showLayersSheet(context);
  }

  Future<void> _openSettings() async {
    await openSettings(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _compassSub?.cancel();
    _boundState?.removeListener(_syncFavorites);
    _followDebounce?.cancel();
    _camSaveDebounce?.cancel();
    _gpsSaveDebounce?.cancel();
    _watchdog?.cancel();
    _autoRecover?.cancel();
    _scrimTimer?.cancel();
    _notifThrottle?.cancel();
    _autoNightTimer?.cancel();
    limits.dispose();
    nav?.dispose();
    transitRide?.dispose();
    engine.disposeEngine();
    location.dispose();
    super.dispose();
  }
}

/// Full-screen boot card shown until the very first style load. Makes the
/// loading state explicit — no silent solid background, ever.
class _MapBoot extends StatefulWidget {
  const _MapBoot({required this.theme});
  final LuxTheme theme;

  @override
  State<_MapBoot> createState() => _MapBootState();
}

class _MapBootState extends State<_MapBoot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Container(
      color: t.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.08).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              ),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.near_me_rounded, size: 40, color: t.primary),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              S.of('appName'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: t.onBackground,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of('mapLoading'),
              style: TextStyle(fontSize: 14.5, color: t.textMuted),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: t.primary,
              ),
            ),
            const SizedBox(height: 34),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                S.of('mapLoadingSub'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small glass status chip (updating / simplified mode).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// The map could not load in any mode — explicit card, user stays in
/// control (retry / simplified).
class _MapFatal extends StatelessWidget {
  const _MapFatal({
    required this.theme,
    required this.onRetry,
    required this.onSimple,
  });
  final LuxTheme theme;
  final VoidCallback onRetry;
  final VoidCallback onSimple;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      color: t.background.withValues(alpha: 0.97),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 36,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                S.of('mapLoadFailed'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: t.onBackground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.of('mapLoadFailedSub'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: t.textMuted),
              ),
              const SizedBox(height: 22),
              PrimaryButton(label: S.of('retry'), onTap: onRetry),
              const SizedBox(height: 10),
              TextButton(onPressed: onSimple, child: Text(S.of('simpleMode'))),
            ],
          ),
        ),
      ),
    );
  }
}

/// v5.8 → v6: the map scale badge. Computes metres-per-pixel from the live
/// camera zoom and shows a nice round distance. v6: the RECTANGULAR ruler
/// layout is gone («прямоугольный макет со шкалой занимает место») — the
/// distance now lives in a ROUND badge in the circle language of the other
/// map controls. Polls the engine every 800 ms.
class _ScaleBar extends StatefulWidget {
  const _ScaleBar({required this.engine});
  final MapEngine engine;

  @override
  State<_ScaleBar> createState() => _ScaleBarState();
}

class _ScaleBarState extends State<_ScaleBar> {
  Timer? _t;
  double _zoom = 12;
  double _lat = 48.8566;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 800), (_) {
      final pos = widget.engine.cameraPosition;
      if (pos == null || !mounted) return;
      if ((pos.zoom - _zoom).abs() < 0.01 &&
          (pos.target.latitude - _lat).abs() < 0.0005) {
        return;
      }
      setState(() {
        _zoom = pos.zoom;
        _lat = pos.target.latitude;
      });
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  (String, String) _niceDistance(double meters) {
    const steps = [
      (20.0, '20', 'м'),
      (50.0, '50', 'м'),
      (100.0, '100', 'м'),
      (200.0, '200', 'м'),
      (500.0, '500', 'м'),
      (1000.0, '1', 'км'),
      (2000.0, '2', 'км'),
      (5000.0, '5', 'км'),
      (10000.0, '10', 'км'),
      (20000.0, '20', 'км'),
      (50000.0, '50', 'км'),
      (100000.0, '100', 'км'),
      (200000.0, '200', 'км'),
      (500000.0, '500', 'км'),
    ];
    for (final s in steps) {
      if (meters <= s.$1) return (s.$2, s.$3);
    }
    return ('1000', 'км');
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    // Web-Mercator ground resolution for 512 px tiles.
    final mpp =
        40075016.686 *
        math.cos(_lat * math.pi / 180) /
        (512 * math.pow(2, _zoom));
    final (value, unit) = _niceDistance(90 * mpp);
    // The ROUND scale badge — same glass circle as the map buttons,
    // distance stacked value + unit inside («сделай ее в круглую кнопку»).
    return Tooltip(
      message: S.of('scaleBadge'),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: t.isDark ? t.surface.withValues(alpha: 0.96) : t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.outline.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: value.length > 3 ? 11.5 : 12.5,
                height: 1.05,
                fontWeight: FontWeight.w800,
                color: t.onBackground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// v5.8: the LONG-PRESS map menu — four quick power actions over the
/// pressed point.
class _MapLongPressMenu extends StatelessWidget {
  const _MapLongPressMenu({
    required this.place,
    required this.onRouteHere,
    required this.onRouteFrom,
    required this.onFavorite,
    required this.onShare,
  });

  final LuxPlace place;
  final VoidCallback onRouteHere;
  final VoidCallback onRouteFrom;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    Widget row(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? accent,
    }) {
      return ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, size: 21, color: accent ?? t.primary),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: t.onBackground,
          ),
        ),
        onTap: onTap,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            place.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
        ),
        row(Icons.navigation_rounded, S.of('routeHere'), onRouteHere),
        row(
          Icons.trip_origin_rounded,
          S.of('routeFromHere'),
          onRouteFrom,
          accent: t.secondary,
        ),
        row(
          Icons.star_rounded,
          S.of('savePlace'),
          onFavorite,
          accent: const Color(0xFFF2A93B),
        ),
        row(Icons.share_rounded, S.of('share'), onShare, accent: t.textMuted),
      ],
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Material(
      color: t.isDark ? t.surface.withValues(alpha: 0.96) : t.surface,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: t.outline.withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: t.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  S.of('searchHint'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.textMuted, fontSize: 14.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCapsule extends StatelessWidget {
  const _ModeCapsule({required this.mode, required this.onPick});
  final TravelMode mode;
  final ValueChanged<TravelMode> onPick;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    Widget chip(TravelMode m, IconData icon, String tip) {
      final active = m == mode;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => onPick(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active ? t.primary : t.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: active ? t.primary : t.outline.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 21,
              color: active ? t.onPrimary : t.onBackground,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: t.isDark ? t.background.withValues(alpha: 0.85) : t.background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: t.outline.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(TravelMode.car, Icons.directions_car_rounded, S.of('car')),
          const SizedBox(height: 4),
          chip(TravelMode.bike, Icons.directions_bike_rounded, S.of('bike')),
          const SizedBox(height: 4),
          chip(TravelMode.foot, Icons.directions_walk_rounded, S.of('foot')),
          const SizedBox(height: 4),
          chip(
            TravelMode.transit,
            Icons.directions_transit_rounded,
            S.of('transit'),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    super.key,
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onRouteTo,
    required this.onModeChanged,
    required this.onClose,
    this.canStart = true,
    this.onPickAlt,
    // v5.7: public transport.
    this.onTransitStart,
    this.onTransitPick,
    // v5.7: route overview while navigating.
    this.onOverview,
    this.overviewActive = false,
  });

  final AppState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<LuxPlace> onRouteTo;
  final ValueChanged<TravelMode> onModeChanged;
  final VoidCallback onClose;

  /// v5.3: whether the route starts at the device (turn-by-turn possible).
  final bool canStart;

  /// v5.5: switch to another route variant.
  final ValueChanged<int>? onPickAlt;

  /// v5.7: transit callbacks.
  final VoidCallback? onTransitStart;
  final ValueChanged<int>? onTransitPick;

  /// v5.7: route overview toggle (car + transit HUD).
  final VoidCallback? onOverview;
  final bool overviewActive;

  @override
  Widget build(BuildContext context) {
    switch (state.navPhase) {
      case NavPhase.routing:
        return GlassCard(
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 14),
              Text(S.of('calculating')),
            ],
          ),
        );
      case NavPhase.preview:
        // v5.7: the TRANSIT preview — departure options + colored legs.
        if (state.isTransit) {
          return TransitPreviewCard(
            state: state,
            onStart: onTransitStart ?? onStart,
            onClose: onClose,
            onPick: onTransitPick ?? (_) {},
            onModeChanged: onModeChanged,
          );
        }
        return RoutePreviewCard(
          state: state,
          canStart: canStart,
          onStart: onStart,
          onClose: onClose,
          onModeChanged: onModeChanged,
          onPickAlt: onPickAlt,
        );
      case NavPhase.navigating || NavPhase.rerouting:
        // v5.7: the TRANSIT HUD while riding the itinerary.
        if (state.isTransit) {
          return TransitHud(
            state: state,
            onStop: onStop,
            onOverview: onOverview,
            overviewActive: overviewActive,
          );
        }
        return NavHud(
          state: state,
          onStop: onStop,
          onOverview: onOverview,
          overviewActive: overviewActive,
        );
      case NavPhase.arrived:
        // v5.8: the premium arrival summary — time / distance / average
        // speed + Save / Share / Done.
        return ArrivalSummaryCard(
          state: state,
          onClose: onClose,
          onSave: state.destination == null
              ? null
              : () async {
                  final st = context.read<AppState>();
                  await st.toggleFavorite(st.destination!);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of('savedTo')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
          onShare: state.destination == null
              ? null
              : () => NavNotifications.shareText(
                  S.of('arrived'),
                  '${S.of('arrived')}: ${state.destination!.name}\n'
                  'https://www.openstreetmap.org/?mlat=${state.destination!.lat}&mlon=${state.destination!.lon}#map=17/${state.destination!.lat}/${state.destination!.lon}',
                ),
        );
      case NavPhase.idle:
        if (state.routeError != null) {
          return GlassCard(
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent.shade200,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(state.routeError!)),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
    }
  }
}
