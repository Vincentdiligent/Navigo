/// Nominatim search + reverse geocoding (documented usage policy: 1 req/s,
/// meaningful UA).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_state.dart';

class Geocoding {
  Geocoding({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _ua = {'User-Agent': 'Navigo/3.0 (Android; navigator app)'};

  /// The suggestion entry point: Photon first, Nominatim as the fallback.
  ///
  /// v6.7: this is what makes the list feel exact. Measured against the same
  /// host — Nominatim needs the words to match a stored name, while Photon
  /// (same OSM data, an index built for autocomplete) resolves «auchan bo»,
  /// «auchan bordx» and «pharmacie bordeaux» — and it geo-ranks around
  /// [near] on its own.
  Future<List<LuxPlace>> suggest(
    String query, {
    LuxCam? near,
    String? language,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];
    List<LuxPlace>? local;
    try {
      local = await _photon(q, near: near, language: language);
    } catch (_) {
      local = null;
    }
    if (local != null && local.isNotEmpty) return local;
    return search(q, near: near, language: language);
  }

  Future<List<LuxPlace>> _photon(
    String q, {
    LuxCam? near,
    String? language,
  }) async {
    final params = <String, String>{
      'q': q,
      'limit': '8',
      'lang': _photonLang(language),
      if (near != null) 'lat': near.lat.toStringAsFixed(5),
      if (near != null) 'lon': near.lon.toStringAsFixed(5),
    };
    final res = await _client
        .get(Uri.https('photon.komoot.io', 'api', params), headers: _ua)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('photon HTTP ${res.statusCode}');
    final feats = (jsonDecode(res.body) as Map<String, dynamic>)['features'];
    if (feats is! List) return [];
    final out = <LuxPlace>[];
    final seen = <String>{};
    for (final raw in feats) {
      final f = raw as Map<String, dynamic>;
      final p = f['properties'];
      final geom = f['geometry'];
      if (p is! Map || geom is! Map) continue;
      final coords = geom['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lon = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      String s(String k) => (p[k] as String?)?.trim() ?? '';
      final street = [
        s('street'),
        s('housenumber'),
      ].where((e) => e.isNotEmpty).join(' ');
      final name = [
        s('name'),
        street,
        s('city'),
        s('state'),
        s('country'),
      ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
      if (name.isEmpty) continue;
      final sub = [
        street,
        s('postalcode'),
        s('city'),
        s('state'),
        s('country'),
      ].where((e) => e.isNotEmpty && e != name).toSet().join(', ');
      // Photon's union index hands back the same object twice now and then.
      if (!seen.add(
        '${p['osm_id']}|${lat.toStringAsFixed(5)},'
        '${lon.toStringAsFixed(5)}',
      )) {
        continue;
      }
      out.add(
        LuxPlace(
          name: name,
          subtitle: sub,
          lat: lat,
          lon: lon,
          kind: 'place',
          distanceKm: near == null ? null : _km(near.lat, near.lon, lat, lon),
        ),
      );
    }
    return out;
  }

  /// The public instance only speaks default/de/en/fr — `lang=ru` is an
  /// error, while `default` returns local names, which is what ru/es want.
  static String _photonLang(String? tag) {
    final code = (tag ?? 'en').toLowerCase();
    if (code.startsWith('fr')) return 'fr';
    if (code.startsWith('de')) return 'de';
    if (code.startsWith('en')) return 'en';
    return 'default';
  }

  /// Nominatim search, biased towards [near].
  ///
  /// v6.7: the plain query used to return whatever matched globally, so a
  /// user standing in France got hits in another country («поиск должен быть
  /// адаптирован»). The viewbox biases the ranking and the distance sort
  /// puts the nearby match on top — but results are NOT bounded, so a query
  /// about a place that really is elsewhere still resolves.
  Future<List<LuxPlace>> search(
    String query, {
    LuxCam? near,
    String? language,
  }) async {
    if (query.trim().length < 2) return [];
    final params = <String, String>{
      'q': query.trim(),
      'format': 'jsonv2',
      'limit': '12',
      'addressdetails': '1',
      if (language != null && language.isNotEmpty) 'accept-language': language,
      if (near != null) 'viewbox': _viewbox(near),
      if (near != null) 'bounded': '0',
    };
    final url = Uri.https('nominatim.openstreetmap.org', 'search', params);
    final res = await _client
        .get(url, headers: _ua)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(res.body) as List;
    final scored = <_Hit>[];
    for (var i = 0; i < list.length; i++) {
      final j = list[i] as Map<String, dynamic>;
      final lat = double.parse(j['lat'] as String);
      final lon = double.parse(j['lon'] as String);
      final parts = (j['display_name'] as String).split(',');
      final name = parts.first.trim();
      final sub = parts.length > 2
          ? parts.sublist(1, parts.length - 1).join(',').trim()
          : '';
      final km = near == null ? null : _km(near.lat, near.lon, lat, lon);
      final place = LuxPlace(
        name: name,
        subtitle: sub,
        lat: lat,
        lon: lon,
        kind: 'place',
        distanceKm: km,
      );
      final importance = (j['importance'] as num?)?.toDouble() ?? 0;
      scored.add(_Hit(importance + _proximityBoost(km), i, place));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.rank.compareTo(b.rank);
    });
    return scored.map((h) => h.place).toList();
  }

  /// ±1.5° ≈ 160 km around the anchor — the «local region» Nominatim leans
  /// the ranking towards.
  static String _viewbox(LuxCam c) {
    const d = 1.5;
    return '${c.lon - d},${c.lat + d},${c.lon + d},${c.lat - d}';
  }

  /// POI-level matches all carry an importance of ~0.0001, so any boost here
  /// orders them purely by distance; a town or landmark (0.3-1.0+) still
  /// outranks a minor local namesake.
  static double _proximityBoost(double? km) => switch (km) {
    null => 0,
    <= 5 => 0.45,
    <= 25 => 0.30,
    <= 100 => 0.18,
    <= 400 => 0.08,
    _ => 0,
  };

  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Reverse geocode a dropped pin; returns the best display name.
  Future<LuxPlace> reverse(double lat, double lon) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=$lat&lon=$lon&format=jsonv2&zoom=18',
    );
    final res = await _client
        .get(url, headers: _ua)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      return LuxPlace(
        name: '0.0000, 0.0000'.replaceFirst('0.0000, 0.0000', '$lat, $lon'),
        lat: lat,
        lon: lon,
      );
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final name =
        (j['display_name'] as String?)?.split(',').first ?? '$lat, $lon';
    return LuxPlace(
      name: name,
      subtitle: j['display_name'] as String? ?? '',
      lat: lat,
      lon: lon,
      kind: 'place',
    );
  }
}

/// One result with its local-relevance score; [rank] keeps the server order
/// as the tie-break so the sort stays deterministic.
class _Hit {
  const _Hit(this.score, this.rank, this.place);
  final double score;
  final int rank;
  final LuxPlace place;
}
