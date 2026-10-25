/// v5.7: PUBLIC TRANSPORT routing — the user in France asked «почему нету
/// добраться по общественному транспорту? … по автобусе или поезде …
/// сделай найди взломай реализуй так чтобы без апи или сам найди апи».
///
/// The answer: **Transitous** (https://api.transitous.org) — a FREE,
/// keyless, community-operated MOTIS router that aggregates OFFICIAL GTFS
/// feeds worldwide. France rides the real IDFM / RATP / SNCF feeds: metro
/// lines with their official colors, RER, trams, buses, live delays.
/// Verified live from this project:
///   • geocode:  GET /api/v1/geocode?text=…                → stops/addresses
///   • plan:     GET /api/v2/plan?fromPlace=lat,lng&toPlace=lat,lng
///                          [&time=ISO8601][&minItineraries=N]
///   • legGeometry.points = encoded polyline with `precision` (1e6 here).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'transit_model.dart';

class TransitService {
  TransitService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _base = 'https://api.transitous.org';
  static const _ua = {'User-Agent': 'Navigo/5.7 (Android; navigator app)'};

  /// Fallback palette for feeds that ship no routeColor (line name drives
  /// the pick — stable per line, premium-looking on every theme).
  static const _palette = [
    '#3F6C51', '#B3554D', '#8A6D3B', '#5C7FA3', '#7B5C9E',
    '#4E8A7C', '#A8763E', '#6D7F5C', '#96628F', '#57708F',
  ];

  /// Fetch up to [count] door-to-door itineraries leaving around [when].
  Future<List<TransitItinerary>> plan({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    DateTime? when,
    int count = 6,
  }) async {
    final t = (when ?? DateTime.now()).toUtc();
    // MOTIS needs an explicit Z-suffixed ISO instant — toIso8601String()
    // + split('.') would drop the 'Z' and the API answers HTTP 400.
    final time =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}'
        'T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}Z';
    final url = Uri.parse(
      '$_base/api/v2/plan'
      '?fromPlace=${fromLat.toStringAsFixed(6)},${fromLon.toStringAsFixed(6)}'
      '&toPlace=${toLat.toStringAsFixed(6)},${toLon.toStringAsFixed(6)}'
      '&time=${Uri.encodeComponent(time)}'
      '&minItineraries=$count',
    );
    final res = await _client.get(url, headers: _ua).timeout(
          const Duration(seconds: 25),
        );
    if (res.statusCode != 200) {
      throw Exception('Transitus HTTP ${res.statusCode}');
    }
    final doc = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (doc['itineraries'] as List?) ?? const [];
    final out = <TransitItinerary>[];
    for (final it in raw) {
      try {
        final parsed = _itinerary(it as Map<String, dynamic>);
        if (parsed != null) out.add(parsed);
      } catch (_) {
        // One malformed itinerary must not kill the whole list.
      }
    }
    if (out.isEmpty) {
      throw Exception('no itineraries');
    }
    // Sort: the fastest door-to-door ride first.
    out.sort((a, b) => a.durationSec.compareTo(b.durationSec));
    return out.take(count).toList();
  }

  TransitItinerary? _itinerary(Map<String, dynamic> it) {
    final legs = <TransitLeg>[];
    for (final l in (it['legs'] as List? ?? const [])) {
      try {
        final leg = _leg(l as Map<String, dynamic>);
        if (leg != null) legs.add(leg);
      } catch (_) {}
    }
    if (legs.isEmpty) return null;
    final transfers = (it['transfers'] as num?)?.toInt() ?? 0;
    return TransitItinerary(
      depart: legs.first.depart,
      arrive: legs.last.arrive,
      durationSec: (it['duration'] as num?)?.toInt() ??
          legs.fold<int>(0, (s, l) => s + l.durationSec),
      transfers: transfers,
      legs: legs,
    );
  }

  TransitLeg? _leg(Map<String, dynamic> j) {
    final modeStr = (j['mode'] as String? ?? 'WALK').toUpperCase();
    final line = (j['routeShortName'] as String? ?? '').trim();
    final isRide = line.isNotEmpty || _isVehicleMode(modeStr);
    final points = decodePolyline(
      ((j['legGeometry'] as Map?)?['points'] as String?) ?? '',
      precision: ((j['legGeometry'] as Map?)?['precision'] as num?)?.toInt() ?? 5,
    );
    if (points.length < 2) return null;
    final colorRaw = (j['routeColor'] as String? ?? '').trim();
    final fallback = _palette[line.isEmpty
        ? 0
        : line.hashCode.abs() % _palette.length];
    final color = colorRaw.isEmpty
        ? fallback
        : '#${colorRaw.replaceAll('#', '').padLeft(6, '0')}';
    final textRaw = (j['routeTextColor'] as String? ?? '').trim();

    final stops = <TransitStop>[];
    void addStop(Map<String, dynamic>? s, DateTime? time) {
      if (s == null) return;
      final lat = (s['lat'] as num?)?.toDouble();
      final lon = (s['lng'] as num?)?.toDouble() ?? (s['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return;
      stops.add(TransitStop(
        name: (s['name'] as String? ?? '').trim(),
        lat: lat,
        lon: lon,
        time: time,
      ));
    }

    final from = j['from'] as Map<String, dynamic>?;
    final to = j['to'] as Map<String, dynamic>?;
    final depTime = DateTime.tryParse(j['startTime'] as String? ?? '')?.toUtc();
    final arrTime = DateTime.tryParse(j['endTime'] as String? ?? '')?.toUtc();
    for (final s in (j['intermediateStops'] as List? ?? const [])) {
      addStop(s as Map<String, dynamic>, null);
    }

    return TransitLeg(
      mode: _modeOf(modeStr, isRide),
      fromName: (from?['name'] as String? ?? '').trim(),
      toName: (to?['name'] as String? ?? '').trim(),
      fromLat: (from?['lat'] as num?)?.toDouble() ?? points.first[0],
      fromLon: (from?['lng'] as num?)?.toDouble() ??
          (from?['lon'] as num?)?.toDouble() ??
          points.first[1],
      toLat: (to?['lat'] as num?)?.toDouble() ?? points.last[0],
      toLon: (to?['lng'] as num?)?.toDouble() ??
          (to?['lon'] as num?)?.toDouble() ??
          points.last[1],
      depart: depTime ?? DateTime.now().toUtc(),
      arrive: arrTime ?? DateTime.now().toUtc(),
      durationSec: (j['duration'] as num?)?.toInt() ?? 60,
      distanceM: (j['distance'] as num?)?.toDouble() ?? 0,
      points: points,
      line: line,
      color: color,
      textColor: textRaw.isEmpty ? '#ffffff' : '#$textRaw',
      headsign: (j['headsign'] as String? ?? '').trim(),
      agency: (j['agencyName'] as String? ?? '').trim(),
      realTime: (j['realTime'] as bool?) ?? false,
      stops: stops,
    );
  }

  bool _isVehicleMode(String m) =>
      m != 'WALK' && m != 'TRANSFER' && m != 'BIKE' && m != 'CAR';

  TransitMode _modeOf(String m, bool ride) {
    if (m == 'WALK' || m == 'TRANSFER' || (!ride && m != 'BUS')) {
      return TransitMode.walk;
    }
    return switch (m) {
      'SUBWAY' || 'METRO' => TransitMode.subway,
      'TRAM' || 'CABLE_TRAM' || 'LIGHT_RAIL' || 'STREETCAR' => TransitMode.tram,
      'RAIL' ||
      'REGIONAL_RAIL' ||
      'HIGH_SPEED_RAIL' ||
      'LONG_DISTANCE' ||
      'COACH' ||
      'AIR' =>
        TransitMode.rail,
      'FERRY' || 'GONDOLA' || 'FUNICULAR' => TransitMode.ferry,
      'BUS' => TransitMode.bus,
      _ => TransitMode.other,
    };
  }

  /// Decodes a Google-encoded polyline (MOTIS returns precision 6).
  static List<List<double>> decodePolyline(
    String s, {
    int precision = 5,
  }) {
    if (s.isEmpty) return const [];
    final factor = _pow10(precision);
    final out = <List<double>>[];
    var i = 0;
    var lat = 0, lng = 0;
    while (i < s.length) {
      var result = 0, shift = 0, b;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      result = 0;
      shift = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      out.add([lat / factor, lng / factor]);
    }
    return out;
  }

  static double _pow10(int n) {
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}
