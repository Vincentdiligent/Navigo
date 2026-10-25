/// Real routing for car, bike and foot — v5.5 (alternatives + options).
///
/// v5.4 lesson: RACING every endpoint in parallel gives a route in 2–4 s.
/// v5.5 adds what the user asked («быстрее маршрут, короче, платные /
/// бесплатные дороги и т.д.»):
///   • ALTERNATIVES — OSRM `alternatives=3` + Valhalla `alternates`;
///   • AVOID OPTIONS — FOSSGIS OSRM rejects `exclude=toll` (InvalidValue,
///     verified live), so avoid-flags are implemented on VALHALLA costing
///     options (use_tolls / use_highways / use_ferries), which are fully
///     supported. When any avoid-flag is set the service asks Valhalla
///     FIRST and only falls back to OSRM if Valhalla fails;
///   • each Valhalla summary reports has_toll / has_highway / has_ferry,
///     surfaced as badges in the route preview.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_state.dart';

class RouteStep {
  const RouteStep({
    required this.name,
    required this.maneuver,
    required this.meters,
    required this.seconds,
    required this.lat,
    required this.lon,
    this.bearingAfter = 0,
  });
  final String name;
  final String maneuver; // e.g. turn|left
  final double meters, seconds;
  final double lat, lon;
  final double bearingAfter;

  String get key => '$maneuver';
}

class LuxRoute {
  const LuxRoute({
    required this.line,
    required this.meters,
    required this.seconds,
    required this.steps,
    this.hasToll = false,
    this.hasHighway = false,
    this.hasFerry = false,
  });
  final List<List<double>> line; // [lat, lon]
  final double meters, seconds;
  final List<RouteStep> steps;

  /// v5.5: badges from the Valhalla summary (only Valhalla fills these).
  final bool hasToll, hasHighway, hasFerry;
}

/// v5.5: user's avoid preferences (car profile; bike/foot ignore them).
class RouteOptions {
  const RouteOptions({
    this.avoidTolls = false,
    this.avoidMotorways = false,
    this.avoidFerries = false,
  });
  final bool avoidTolls;
  final bool avoidMotorways;
  final bool avoidFerries;

  bool get any => avoidTolls || avoidMotorways || avoidFerries;
}

/// Per-mode OSRM base list (FOSSGIS hosts one server per profile). The demo
/// server (router.project-osrm.org) serves car only.
List<String> _osrmBases(TravelMode mode) => switch (mode) {
      TravelMode.car => [
          'https://routing.openstreetmap.de/routed-car',
          'https://router.project-osrm.org',
          'https://routing.openstreetmap.de/routed-car',
        ],
      TravelMode.bike => [
          'https://routing.openstreetmap.de/routed-bike',
          'https://routing.openstreetmap.de/routed-bike',
        ],
      TravelMode.foot => [
          'https://routing.openstreetmap.de/routed-foot',
          'https://routing.openstreetmap.de/routed-foot',
        ],
      // Never used (transit rides Transitous); a safe fallback.
      TravelMode.transit => [
          'https://routing.openstreetmap.de/routed-foot',
        ],
      };

/// Valhalla costing per mode (an entirely different routing engine —
/// different code, different data snapshot, different operator).
const String kValhallaUrl = 'https://valhalla1.openstreetmap.de/route';

String _valhallaCosting(TravelMode mode) => switch (mode) {
      TravelMode.car => 'auto',
      TravelMode.bike => 'bicycle',
      TravelMode.foot => 'pedestrian',
      TravelMode.transit => 'pedestrian', // never used — transit rides Transitous
    };

class RouteService {
  RouteService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// ALL route variants for the request (fastest first). RACES OSRM +
  /// Valhalla when no avoid-flag is set; asks Valhalla FIRST when the user
  /// excluded tolls / motorways / ferries (only Valhalla honours them).
  ///
  /// v5.8: [via] — intermediate stops (A → B → C → D). OSRM takes them as
  /// extra coordinates, Valhalla as 'through' locations.
  Future<List<LuxRoute>> fetchRoutes({
    required TravelMode mode,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    List<LuxPlace> via = const [],
    RouteOptions options = const RouteOptions(),
    bool alternatives = true,
  }) async {
    final List<Future<List<LuxRoute>>> attempts;
    if (mode == TravelMode.car && options.any) {
      // Avoid-flags: Valhalla is the ONLY backend that honours them —
      // try it first, OSRM (unfiltered) is the fallback.
      attempts = [
        _fetchValhalla(
          mode: mode,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          via: via,
          options: options,
          alternatives: alternatives,
        ),
        _raceOsrm(
          mode: mode,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          via: via,
          alternatives: alternatives,
        ),
      ];
    } else {
      attempts = [
        _raceOsrm(
          mode: mode,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          via: via,
          alternatives: alternatives,
        ),
        _fetchValhalla(
          mode: mode,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          via: via,
          options: options,
          alternatives: alternatives,
        ),
      ];
    }
    try {
      final all = await _firstValid(attempts);
      return _sortAndDedup(all);
    } catch (e) {
      throw Exception('routing failed on every backend: $e');
    }
  }

  /// The single best route (reroute / guidance start).
  Future<LuxRoute> fetchRoute({
    required TravelMode mode,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    List<LuxPlace> via = const [],
    RouteOptions options = const RouteOptions(),
  }) async {
    final all = await fetchRoutes(
      mode: mode,
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      via: via,
      options: options,
      alternatives: false,
    );
    return all.first;
  }

  /// Fastest variant first; drop near-duplicates (same distance ±40 m and
  /// same duration ±90 s are the same road with tiny data differences).
  static List<LuxRoute> _sortAndDedup(List<LuxRoute> routes) {
    final sorted = [...routes]..sort((a, b) => a.seconds.compareTo(b.seconds));
    final out = <LuxRoute>[];
    for (final r in sorted) {
      final dup = out.any(
        (o) =>
            (o.meters - r.meters).abs() < 40 && (o.seconds - r.seconds).abs() < 90,
      );
      if (!dup) out.add(r);
    }
    return out.take(3).toList();
  }

  /// Returns the first future that completes with a VALID answer; failures
  /// are swallowed while at least one attempt is still alive.
  static Future<List<LuxRoute>> _firstValid(
    List<Future<List<LuxRoute>>> futures,
  ) {
    final completer = Completer<List<LuxRoute>>();
    var pending = futures.length;
    for (final f in futures) {
      f.then((r) {
        if (!completer.isCompleted) completer.complete(r);
      }).catchError((Object e) {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.completeError(e);
        }
      });
    }
    return completer.future;
  }

  Future<List<LuxRoute>> _raceOsrm({
    required TravelMode mode,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required List<LuxPlace> via,
    required bool alternatives,
  }) {
    final attempts = <Future<List<LuxRoute>>>[
      for (final base in _osrmBases(mode))
        _fetchOsrm(
          base: base,
          mode: mode,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          via: via,
          alternatives: alternatives,
        ),
    ];
    return _firstValid(attempts);
  }

  Future<List<LuxRoute>> _fetchOsrm({
    required String base,
    required TravelMode mode,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required List<LuxPlace> via,
    required bool alternatives,
  }) async {
    // v5.8: A → via1 → via2 … → B. OSRM wants [lon,lat] pairs joined with
    // ';'. With more than two points alternatives are ignored by OSRM —
    // harmless (the response just has none).
    final coords = [
      '$fromLon,$fromLat',
      for (final p in via) '${p.lon},${p.lat}',
      '$toLon,$toLat',
    ].join(';');
    final url = '$base/route/v1/$mode/'
        '$coords'
        '?overview=full&geometries=geojson&steps=true'
        '${alternatives && via.isEmpty ? '&alternatives=3' : ''}';
    final res = await _client
        .get(Uri.parse(url), headers: {'User-Agent': 'Navigo/3.0 (Android)'})
        .timeout(const Duration(seconds: 9));
    if (res.statusCode != 200) {
      throw Exception('OSRM HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final code = body['code'] as String?;
    if (code != 'Ok') {
      throw Exception('OSRM code $code');
    }
    final routes = body['routes'] as List;
    if (routes.isEmpty) throw Exception('OSRM empty routes');

    final out = <LuxRoute>[];
    for (final rRaw in routes) {
      final r0 = rRaw as Map<String, dynamic>;
      final coords = (((r0['geometry'] as Map)['coordinates']) as List)
          .map<List<double>>(
            // OSRM speaks [lon, lat]; the app works with [lat, lon].
            (c) => [(c[1] as num).toDouble(), (c[0] as num).toDouble()],
          )
          .toList();
      if (coords.length < 2) continue;
      final steps = <RouteStep>[];
      final legs = r0['legs'] as List;
      for (final leg in legs) {
        for (final s in (leg as Map)['steps'] as List) {
          final step = s as Map<String, dynamic>;
          final man = (step['maneuver'] ?? {}) as Map<String, dynamic>;
          final loc = (man['location'] ?? [0, 0]) as List;
          steps.add(
            RouteStep(
              name: (step['name'] ?? '') as String,
              maneuver:
                  '${man['type'] ?? 'continue'}|${man['modifier'] ?? ''}',
              meters: (step['distance'] as num).toDouble(),
              seconds: (step['duration'] as num).toDouble(),
              lat: (loc[1] as num).toDouble(),
              lon: (loc[0] as num).toDouble(),
              bearingAfter: (man['bearing_after'] as num? ?? 0).toDouble(),
            ),
          );
        }
      }
      out.add(
        LuxRoute(
          line: coords,
          meters: (r0['distance'] as num).toDouble(),
          seconds: (r0['duration'] as num).toDouble(),
          steps: steps,
        ),
      );
    }
    if (out.isEmpty) throw Exception('OSRM no usable geometry');
    return out;
  }

  /// Valhalla backend: POST JSON, polyline6 shape, numeric maneuver types.
  /// Honours the avoid-options through costing parameters (verified live:
  /// use_tolls=0 returns a 200 and the summary reports has_toll).
  Future<List<LuxRoute>> _fetchValhalla({
    required TravelMode mode,
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required List<LuxPlace> via,
    required RouteOptions options,
    required bool alternatives,
  }) async {
    final costingOptions = <String, dynamic>{};
    if (mode == TravelMode.car) {
      costingOptions['auto'] = {
        if (options.avoidTolls) 'use_tolls': 0,
        if (options.avoidMotorways) 'use_highways': 0.3,
        if (options.avoidFerries) 'use_ferries': 0,
      };
    }
    final payload = jsonEncode({
      'locations': [
        {'lat': fromLat, 'lon': fromLon, 'type': 'break'},
        for (final p in via)
          {'lat': p.lat, 'lon': p.lon, 'type': 'through'},
        {'lat': toLat, 'lon': toLon, 'type': 'break'},
      ],
      'costing': _valhallaCosting(mode),
      if (costingOptions.isNotEmpty) 'costing_options': costingOptions,
      'directions_type': 'detailed',
      'alternatives': alternatives && via.isEmpty ? 2 : 0,
    });
    final res = await _client
        .post(
          Uri.parse(kValhallaUrl),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'Navigo/3.0 (Android)',
          },
          body: payload,
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Valhalla HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['trip'] == null) {
      throw Exception('Valhalla error ${body['error_code'] ?? ''}');
    }
    final trips = <Map<String, dynamic>>[
      body['trip'] as Map<String, dynamic>,
      if (alternatives)
        for (final aRaw in (body['alternates'] as List? ?? const []))
          if ((aRaw as Map<String, dynamic>)['trip'] is Map<String, dynamic>)
            (aRaw['trip'] as Map<String, dynamic>),
    ];
    final out = <LuxRoute>[];
    for (final trip in trips) {
      final r = _parseValhallaTrip(trip);
      if (r != null) out.add(r);
    }
    if (out.isEmpty) throw Exception('Valhalla empty trip');
    return out;
  }

  LuxRoute? _parseValhallaTrip(Map<String, dynamic> trip) {
    final legs = trip['legs'] as List?;
    if (legs == null || legs.isEmpty) return null;

    // 1) Reassemble the full geometry from per-leg polyline6 shapes.
    final line = <List<double>>[];
    for (final legRaw in legs) {
      final leg = legRaw as Map<String, dynamic>;
      final shape = decodePolyline6(leg['shape'] as String);
      if (line.isNotEmpty && shape.isNotEmpty) line.removeLast();
      line.addAll(shape);
    }
    if (line.length < 2) return null;

    // 2) Flatten maneuvers into the app's step model.
    final steps = <RouteStep>[];
    for (final legRaw in legs) {
      final leg = legRaw as Map<String, dynamic>;
      final shape = decodePolyline6(leg['shape'] as String);
      for (final mRaw in (leg['maneuvers'] as List)) {
        final m = mRaw as Map<String, dynamic>;
        final idx = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
        final lat = idx < shape.length ? shape[idx][0] : line.first[0];
        final lon = idx < shape.length ? shape[idx][1] : line.first[1];
        final names = (m['street_names'] as List?)?.cast<String>() ?? const [];
        steps.add(
          RouteStep(
            name: names.isNotEmpty ? names.first : '',
            maneuver: _valhallaManeuverKey((m['type'] as num?)?.toInt() ?? 9),
            meters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
            seconds: ((m['time'] as num?)?.toDouble() ?? 0),
            lat: lat,
            lon: lon,
          ),
        );
      }
    }
    final summary = (trip['summary'] ?? {}) as Map<String, dynamic>;
    final meters = ((summary['length'] as num?)?.toDouble() ?? 0) * 1000;
    var seconds = 0.0;
    for (final s in steps) {
      seconds += s.seconds;
    }
    if (meters <= 0) {
      // Very short routes can produce an empty summary — measure the line.
      var acc = 0.0;
      for (var i = 1; i < line.length; i++) {
        final dLat = (line[i][0] - line[i - 1][0]) * 111320;
        final dLon = (line[i][1] - line[i - 1][1]) *
            111320 *
            math.cos(line[i][0] * math.pi / 180);
        acc += math.sqrt(dLat * dLat + dLon * dLon);
      }
      return LuxRoute(
        line: line,
        meters: acc,
        seconds: seconds <= 0 ? acc / 12.5 : seconds,
        steps: steps,
        hasToll: summary['has_toll'] == true,
        hasHighway: summary['has_highway'] == true,
        hasFerry: summary['has_ferry'] == true,
      );
    }
    return LuxRoute(
      line: line,
      meters: meters,
      seconds: seconds <= 0
          ? (summary['time'] as num?)?.toDouble() ?? meters / 12.5
          : seconds,
      steps: steps,
      hasToll: summary['has_toll'] == true,
      hasHighway: summary['has_highway'] == true,
      hasFerry: summary['has_ferry'] == true,
    );
  }

  /// Valhalla maneuver type (integer) → the app's «type|modifier» key.
  static String _valhallaManeuverKey(int t) => switch (t) {
        1 || 2 => 'depart|straight', // start / destination
        3 => 'turn|left',
        4 => 'turn|right',
        5 => 'turn|sharp left',
        6 => 'turn|sharp right',
        7 => 'turn|slight left',
        8 => 'turn|slight right',
        9 => 'continue|straight',
        10 => 'roundabout|straight',
        11 => 'exit roundabout|right',
        12 => 'uturn|straight',
        13 => 'merge|straight',
        14 => 'fork|left',
        15 => 'fork|right',
        16 => 'fork|straight',
        17 => 'exit|left',
        18 => 'exit|right',
        19 => 'exit|straight',
        _ => 'continue|straight',
      };

  /// Re-route from a mid-route position (off-route recovery).
  Future<LuxRoute> reroute({
    required TravelMode mode,
    required double lat,
    required double lon,
    required double toLat,
    required double toLon,
  }) =>
      fetchRoute(
        mode: mode,
        fromLat: lat,
        fromLon: lon,
        toLat: toLat,
        toLon: toLon,
      );
}

/// Decodes an encoded polyline (precision 6, the Valhalla format) into
/// [lat, lon] pairs. Standard Google/Mapbox algorithm with 1e6 scale.
List<List<double>> decodePolyline6(String encoded) {
  final out = <List<double>>[];
  var index = 0, lat = 0, lng = 0;
  final n = encoded.length;
  while (index < n) {
    var b = 0, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    out.add([lat / 1e6, lng / 1e6]);
  }
  return out;
}
