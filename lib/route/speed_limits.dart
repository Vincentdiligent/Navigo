/// v5.8: legal SPEED LIMITS of the road the driver is on — the Google-Maps
/// style badge in the navigation HUD.
///
/// The vector tiles (OpenMapTiles schema) do NOT carry `maxspeed` — verified
/// against the live TileJSON (`vector_layers.transportation` has no such
/// field). The legal source is OpenStreetMap itself: a corridor of the route
/// AHEAD is fetched from Overpass (`way["maxspeed"]` + full geometry), cached
/// and re-used while the driver advances; the limit is resolved by projecting
/// the GPS fix onto the nearest cached way.
///
/// One request covers ~1.2 km of the road ahead, so an hour-long drive costs
/// a handful of small queries.
library;

import 'dart:async';

import '../core/geo_math.dart';
import 'overpass.dart';

class _LimitWay {
  _LimitWay(this.limit, this.pts);
  final int limit;
  final List<List<double>> pts;
}

class SpeedLimitEngine {
  SpeedLimitEngine(this._op);

  final Overpass _op;

  final List<_LimitWay> _ways = [];
  String _bboxKey = '';
  bool _fetching = false;
  Timer? _corridorTimer;

  /// The last known limit. [lastChangedAt] lets the UI hide the badge when
  /// the value went stale (off-road, yard, tunnel, no OSM data).
  int? lastLimit;
  DateTime lastChangedAt = DateTime.now();

  void dispose() {
    _corridorTimer?.cancel();
  }

  /// Call on every GPS fix. [ahead] — the remaining route polyline; only the
  /// next few km are used. Null outside navigation (the badge is HUD-only).
  Future<void> update(double lat, double lon, List<List<double>>? ahead) async {
    if (ahead == null || ahead.length < 2) return;
    _maybePrefetchCorridor(ahead);
    _resolveFromCache(lat, lon);
  }

  // ── corridor prefetch ───────────────────────────────────────────────────
  void _maybePrefetchCorridor(List<List<double>> ahead) {
    // 1.2 km of the road ahead (+60 m halo) — small bbox, small answer.
    final chunk = trimToLength(ahead, 1200);
    if (chunk.length < 2) return;
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in chunk) {
      if (p[0] < minLat) minLat = p[0];
      if (p[0] > maxLat) maxLat = p[0];
      if (p[1] < minLon) minLon = p[1];
      if (p[1] > maxLon) maxLon = p[1];
    }
    minLat -= 0.0006;
    maxLat += 0.0006;
    minLon -= 0.0006;
    maxLon += 0.0006;
    final key = '${minLat.toStringAsFixed(4)},${minLon.toStringAsFixed(4)},'
        '${maxLat.toStringAsFixed(4)},${maxLon.toStringAsFixed(4)}';
    if (key == _bboxKey || _fetching) return;

    // The cached corridor must cover the road AHEAD: prefetch when the fix
    // is inside the old bbox but already halfway through the chunk.
    final dToEnd = distanceM(
      chunk.first[0],
      chunk.first[1],
      chunk.last[0],
      chunk.last[1],
    );
    if (_bboxKey.isNotEmpty && dToEnd < 600) return;

    _bboxKey = key;
    _fetching = true;
    () async {
      try {
        final ql = '[out:json][timeout:15];'
            'way["maxspeed"]($minLat,$minLon,$maxLat,$maxLon);'
            'out geom 40;';
        final json = await _op.query(ql);
        if (json == null) return;
        final els = json['elements'] as List? ?? const [];
        final fresh = <_LimitWay>[];
        for (final e in els) {
          if (e is! Map || e['type'] != 'way') continue;
          final lim = parseMaxspeed(e['tags'] as Map?);
          if (lim == null) continue;
          final geom = e['geometry'] as List? ?? const [];
          final pts = <List<double>>[
            for (final g in geom)
              if (g is Map && g['lat'] is num && g['lon'] is num)
                [(g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()],
          ];
          if (pts.length >= 2) fresh.add(_LimitWay(lim, pts));
        }
        if (fresh.isNotEmpty) {
          _ways
            ..clear()
            ..addAll(fresh);
          _corridorTimer?.cancel();
          // The cached corridor expires — the badge hides when we leave it.
          _corridorTimer = Timer(const Duration(minutes: 6), () => _ways.clear);
        }
      } catch (_) {
        // Keep whatever we have; the next fix retries.
      } finally {
        _fetching = false;
      }
    }();
  }

  // ── resolve ──────────────────────────────────────────────────────────────
  void _resolveFromCache(double lat, double lon) {
    _LimitWay? best;
    var bestD = 24.0; // metres — two parallel carriageways apart
    for (final w in _ways) {
      final proj = nearestOnPolyline(lat, lon, w.pts);
      if (proj.distanceM < bestD) {
        bestD = proj.distanceM;
        best = w;
      }
    }
    if (best != null && best.limit != lastLimit) {
      lastLimit = best.limit;
      lastChangedAt = DateTime.now();
    }
  }
}

/// OSM maxspeed value → km/h. Handles plain numbers, lane syntax
/// ("50;60"), French symbolic values, and mph; returns null for
/// un-parseable ones ("signals", "walk", "none").
int? parseMaxspeed(Map? tags) {
  if (tags == null) return null;
  final raw = tags['maxspeed'] ?? tags['maxspeed:forward'];
  if (raw is! String) return null;
  final v = raw.trim();
  const fr = <String, int>{
    'FR:urban': 50,
    'FR:zone30': 30,
    'FR:meet': 20,
    'FR:walk': 20,
    'RU:urban': 60,
    'RU:rural': 90,
  };
  if (fr.containsKey(v)) return fr[v];
  // "50" | "50;60" | "50 mph" — take the first number.
  final m = RegExp(r'^(\d+)').firstMatch(v);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  if (n == null || n < 5 || n > 200) return null;
  if (v.toLowerCase().endsWith('mph')) return (n * 1.609).round();
  return n;
}
