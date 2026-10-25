/// v5.8: shared Overpass API client (OpenStreetMap) — keyless, mirror
/// failover, polite throttling.
///
/// Two engines ride on top of it:
///   • [SpeedLimitEngine] — legal speed limits of the road ahead
///     (`way["maxspeed"]`, geometry included);
///   • [CameraService] — fixed speed cameras (`node["highway"="speed_camera"]`),
///     cached on the device exactly the way OsmAnd does it.
///
/// Mirrors are tried in order until one answers; a global gap between
/// requests keeps us a good citizen of the free endpoints, and a backoff
/// after a full failure prevents hammering during tunnels / outages.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Overpass {
  Overpass();

  static const List<String> _mirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static const _headers = {
    'User-Agent': 'Navigo/5.8 (navigator; personal use)',
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _blackoutUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _next = 0;

  /// v6.7: collapsed per QUERY STRING, not globally. One shared slot used
  /// to hand the running request's payload to EVERY concurrent caller — the
  /// place card fires several Overpass queries at once, so one building's
  /// tags could be shown as another place's info.
  final Map<String, Future<dynamic>> _inflight = {};

  /// Runs one query and returns the decoded JSON (`elements` list) or null
  /// when every mirror failed. Never throws.
  Future<dynamic> query(String ql, {Duration minGap = const Duration(seconds: 8)}) {
    // Collapse concurrent callers of the SAME query only.
    final running = _inflight[ql];
    if (running != null) return running;
    final fut = _query(ql, minGap);
    final wrapped = fut.whenComplete(() => _inflight.remove(ql));
    _inflight[ql] = wrapped;
    return wrapped;
  }

  Future<dynamic> _query(String ql, Duration minGap) async {
    if (DateTime.now().isBefore(_blackoutUntil)) return null;
    final wait = _lastCall.add(minGap).difference(DateTime.now());
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    var lastErr = '';
    for (var i = 0; i < _mirrors.length; i++) {
      final url = _mirrors[(_next + i) % _mirrors.length];
      _lastCall = DateTime.now();
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        final req = await client.postUrl(Uri.parse(url));
        for (final e in _headers.entries) {
          req.headers.set(e.key, e.value);
        }
        req.write('data=${Uri.encodeQueryComponent(ql)}');
        final res = await req.close().timeout(const Duration(seconds: 25));
        final body = await res.transform(utf8.decoder).join();
        client.close(force: true);
        if (res.statusCode == 200 && body.isNotEmpty && body[0] == '{') {
          _next = (_next + i + 1) % _mirrors.length; // round-robin the winner
          return jsonDecode(body);
        }
        lastErr = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastErr = e.toString();
      }
    }
    // Every mirror failed — cool down before the next attempt.
    _blackoutUntil = DateTime.now().add(const Duration(seconds: 60));
    assert(() {
      // ignore: avoid_print
      print('[Navigo] Overpass failed: $lastErr');
      return true;
    }());
    return null;
  }
}
