/// v5.8: SPEED CAMERA warnings — the user: «предупреждения по камерам! ты
/// должен это найти и внедрить правильно!».
///
/// Data: OpenStreetMap `node["highway"="speed_camera"]` via Overpass (the
/// canonical keyless source — the same one OsmAnd uses). Cameras around the
/// position / along the whole route are fetched once, cached as JSON in the
/// app documents dir and re-fetched only when stale (> 14 days) or when the
/// driver travels far outside the cached box.
///
/// Warning model (TomTom-style alerting, simplified to two stages):
///   • stage 1 — the camera enters the approach window (speed-dependent,
///     ≥ 450 m): TTS announcement + HUD chip, ONCE per camera;
///   • stage 2 — 150 m: heavy haptic + the chip pulses red;
///   • passed — the camera falls behind / is passed: it re-arms.
///
/// «Ahead» is decided by projecting the camera onto the remaining route
/// (navigation) or by bearing match (free browsing).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/geo_math.dart';
import 'overpass.dart';
import 'speed_limits.dart' show parseMaxspeed;

class SpeedCam {
  const SpeedCam({
    required this.lat,
    required this.lon,
    this.maxspeed,
  });
  final double lat, lon;

  /// Posted limit of the camera itself, when OSM knows it (drives the
  /// "camera 90" hint; null → unknown).
  final int? maxspeed;

  String get key => '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
}

/// One camera's lifecycle for the current pass.
enum CamPhase { idle, announced, close }

class _CamState {
  CamPhase phase = CamPhase.idle;
}

/// Result of a feed tick — what the HUD / TTS should show.
class CamAlert {
  const CamAlert({
    required this.cam,
    required this.distanceM,
    required this.justAnnounced,
    required this.close,
  });
  final SpeedCam cam;
  final double distanceM;

  /// True on the exact tick the camera entered the approach window (speak
  /// exactly once per camera).
  final bool justAnnounced;
  final bool close;
}

class CameraService {
  CameraService(this._op);

  final Overpass _op;
  final List<SpeedCam> _cams = [];
  final Map<String, _CamState> _states = {};
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Bounding box already covered by [_cams].
  double _minLat = 90, _maxLat = -90, _minLon = 180, _maxLon = -180;
  bool _fetching = false;

  /// Every cached camera — drawn as red map markers along the route.
  List<SpeedCam> get cams => List.unmodifiable(_cams);
  bool get hasData => _cams.isNotEmpty;

  /// Loads the on-device cache. Returns true when something was loaded.
  Future<bool> loadCache() async {
    try {
      final f = File(_cachePath());
      if (!f.existsSync()) return false;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = j['cams'] as List? ?? const [];
      _cams
        ..clear()
        ..addAll([
          for (final e in list)
            if (e is Map)
              SpeedCam(
                lat: (e['lat'] as num).toDouble(),
                lon: (e['lon'] as num).toDouble(),
                maxspeed: e['ms'] == null ? null : (e['ms'] as num).toInt(),
              ),
        ]);
      _minLat = (j['minLat'] as num?)?.toDouble() ?? 90;
      _maxLat = (j['maxLat'] as num?)?.toDouble() ?? -90;
      _minLon = (j['minLon'] as num?)?.toDouble() ?? 180;
      _maxLon = (j['maxLon'] as num?)?.toDouble() ?? -180;
      _fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        (j['ts'] as int?) ?? 0,
      );
      return _cams.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _cachePath() {
    // The app layer injects its documents dir via [documentsDir]; the
    // system-temp fallback only matters for pure-Dart tests.
    final d = documentsDir;
    if (d == null || d.isEmpty) {
      return '${Directory.systemTemp.path}/navigo_speed_cams.json';
    }
    return '$d/navigo_speed_cams.json';
  }

  /// The app layer passes its documents dir (path_provider).
  static String? documentsDir;

  /// Fetches cameras for [bbox] when the current cache does not cover it
  /// (or is stale). [bbox] = (minLat, minLon, maxLat, maxLon).
  Future<void> ensureArea(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) async {
    final now = DateTime.now();
    final stale = now.difference(_fetchedAt).inDays >= 14;
    final covered = _minLat <= minLat + 0.01 &&
        _maxLat >= maxLat - 0.01 &&
        _minLon <= minLon + 0.01 &&
        _maxLon >= maxLon - 0.01;
    if (_fetching || (covered && !stale)) return;
    _fetching = true;
    try {
      final ql = '[out:json][timeout:25];'
          'node["highway"="speed_camera"]($minLat,$minLon,$maxLat,$maxLon);'
          'out body qt;';
      final json = await _op.query(ql, minGap: const Duration(seconds: 2));
      if (json == null) return;
      final els = json['elements'] as List? ?? const [];
      final fresh = <SpeedCam>[];
      for (final e in els) {
        if (e is! Map || e['type'] != 'node') continue;
        final lat = e['lat'];
        final lon = e['lon'];
        if (lat is! num || lon is! num) continue;
        final tags = e['tags'] as Map? ?? const {};
        fresh.add(SpeedCam(
          lat: lat.toDouble(),
          lon: lon.toDouble(),
          maxspeed: parseMaxspeed(tags),
        ));
      }
      if (fresh.isNotEmpty || _cams.isEmpty) {
        _cams
          ..clear()
          ..addAll(fresh);
        _minLat = minLat;
        _maxLat = maxLat;
        _minLon = minLon;
        _maxLon = maxLon;
        _fetchedAt = now;
        await _save();
      } else {
        // Data returned but empty — widen coverage anyway so we don't
        // re-query the same box every minute (area simply has no cameras).
        _fetchedAt = now;
      }
    } catch (_) {
      // Offline / rate limited — cached data (if any) keeps working.
    } finally {
      _fetching = false;
    }
  }

  Future<void> _save() async {
    try {
      final f = File(_cachePath());
      await f.writeAsString(jsonEncode({
        'ts': _fetchedAt.millisecondsSinceEpoch,
        'minLat': _minLat,
        'maxLat': _maxLat,
        'minLon': _minLon,
        'maxLon': _maxLon,
        'cams': [
          for (final c in _cams)
            {'lat': c.lat, 'lon': c.lon, 'ms': c.maxspeed},
        ],
      }));
    } catch (_) {}
  }

  /// Resets the per-camera lifecycle (new route / new pass).
  void resetAlerts() {
    _states.clear();
  }

  /// Finds the most relevant camera ahead and advances its FSM.
  ///
  /// [ahead] — remaining route polyline (navigation). [courseDeg] — the
  /// movement bearing (free browsing). [speedMps] — current speed, scales
  /// the approach window.
  CamAlert? feed(
    double lat,
    double lon, {
    List<List<double>>? ahead,
    double? courseDeg,
    double speedMps = 0,
  }) {
    if (_cams.isEmpty) return null;
    SpeedCam? best;
    var bestD = double.infinity;
    for (final c in _cams) {
      final d = distanceM(lat, lon, c.lat, c.lon);
      if (d > 2500) continue; // never care beyond 2.5 km
      bool isAhead;
      if (ahead != null && ahead.length >= 2) {
        // Navigation: the camera must sit ON the remaining road (lateral ≤
        // 45 m of some segment ahead).
        final proj = nearestOnPolyline(c.lat, c.lon, ahead);
        isAhead = proj.distanceM < 45;
      } else if (courseDeg != null) {
        // Browsing: within a ±55° cone of the movement direction.
        final brg = bearingDeg(lat, lon, c.lat, c.lon);
        var diff = (brg - courseDeg).abs() % 360;
        if (diff > 180) diff = 360 - diff;
        isAhead = diff < 55;
      } else {
        isAhead = false;
      }
      if (!isAhead) continue;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    if (best == null) return null;
    final st = _states.putIfAbsent(best.key, _CamState.new);
    // Re-arm a passed camera when we are far beyond it again (loop roads).
    if (st.phase == CamPhase.close && bestD > 400) st.phase = CamPhase.idle;

    final approach = math.max(450.0, speedMps * 28);
    var justAnnounced = false;
    if (st.phase == CamPhase.idle && bestD < approach && bestD > 140) {
      st.phase = CamPhase.announced;
      justAnnounced = true;
    }
    final close = bestD <= 150;
    if (close && st.phase != CamPhase.close) st.phase = CamPhase.close;
    return CamAlert(
      cam: best,
      distanceM: bestD,
      justAnnounced: justAnnounced,
      close: close,
    );
  }
}

/// Debug-friendly dump for diagnostics.
@visibleForTesting
String camStats(CameraService s) =>
    'cams=${s.cams.length} covered=${s.hasData}';
