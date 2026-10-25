/// Road incidents along the route (v5.5) — the user asked for «аварии,
/// работы, закрытые дороги» on the route screen.
///
/// Honest data contract: there is NO free real-time accident feed. What
/// OpenStreetMap DOES carry is mapped roadworks (`highway=construction`)
/// and physical closures (`barrier=block`). This service asks the public
/// Overpass API for those features inside the route's bbox and returns
/// amber warning points drawn on the map; the preview card shows the count.
/// The lookup is best-effort (9 s timeout) and NEVER blocks the route
/// itself — a failure just means no badges.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/geo_math.dart';

class RoadIncident {
  const RoadIncident(this.lat, this.lon, this.label);
  final double lat, lon;
  final String label;
}

class IncidentService {
  IncidentService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<List<RoadIncident>> fetchAlong(List<List<double>> line) async {
    if (line.length < 2) return const [];
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in line) {
      minLat = math.min(minLat, p[0]);
      maxLat = math.max(maxLat, p[0]);
      minLon = math.min(minLon, p[1]);
      maxLon = math.max(maxLon, p[1]);
    }
    // Pad the bbox a little so edge-clipped roadworks still show.
    const pad = 0.01;
    final bbox =
        '${(minLat - pad).toStringAsFixed(4)},'
        '${(minLon - pad).toStringAsFixed(4)},'
        '${(maxLat + pad).toStringAsFixed(4)},'
        '${(maxLon + pad).toStringAsFixed(4)}';

    // Ways: mapped construction zones (center point). Nodes: physical
    // road blocks (bollards/blocks that close a road for cars).
    final query =
        '[out:json][timeout:8];('
        'way["highway"="construction"]($bbox);'
        'node["barrier"="block"]($bbox);'
        ');out center 60;';

    for (final ep in _endpoints) {
      try {
        final res = await _client
            .post(
              Uri.parse(ep),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'User-Agent': 'Navigo/3.0 (Android)',
              },
              body: 'data=${Uri.encodeComponent(query)}',
            )
            .timeout(const Duration(seconds: 9));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final els = (body['elements'] as List? ?? const []);
        final out = <RoadIncident>[];
        for (final e in els) {
          final el = e as Map<String, dynamic>;
          final lat = (el['lat'] ?? (el['center'] ?? const {})['lat'])
              as num?;
          final lon = (el['lon'] ?? (el['center'] ?? const {})['lon'])
              as num?;
          if (lat == null || lon == null) continue;
          final tags = (el['tags'] ?? const {}) as Map<String, dynamic>;
          final isConstruction = tags['highway'] == 'construction';
          final name = (tags['name'] ?? tags['construction'] ?? '') as String;
          out.add(
            RoadIncident(
              lat.toDouble(),
              lon.toDouble(),
              isConstruction
                  ? (name.isEmpty
                      ? 'Дорожные работы'
                      : 'Дорожные работы · $name')
                  : 'Перекрытие дороги',
            ),
          );
        }
        return _dedup(out);
      } catch (_) {
        continue; // next endpoint / silent give-up
      }
    }
    return const [];
  }

  /// Points closer than 80 m are the same workzone.
  static List<RoadIncident> _dedup(List<RoadIncident> raw) {
    final out = <RoadIncident>[];
    for (final i in raw) {
      final dup = out.any((o) => distanceM(o.lat, o.lon, i.lat, i.lon) < 80);
      if (!dup) out.add(i);
    }
    return out.take(40).toList();
  }
}
