/// GPS stream with permission handling.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationStream {
  StreamSubscription<Position>? _sub;

  Future<bool> ensurePermission() async {
    var ok = await Geolocator.isLocationServiceEnabled();
    if (!ok) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// v6.4: Android's last-known position is a DEVICE-WIDE cache — fed by
  /// ANY app, possibly days old and miles away. That was the «без геолокации
  /// моё расположение показывает рандомно: то на речке, то в центре города»
  /// bug. Only a FRESH fix (≤3 min) is trustworthy enough to show as «я».
  Future<Position?> lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      final fresh = DateTime.now().toUtc()
              .difference(p.timestamp.toUtc())
              .abs() <=
          const Duration(minutes: 3);
      return fresh ? p : null;
    } catch (_) {
      return null;
    }
  }

  Future<Position?> current() async {
    try {
      // v6.4: an explicit time limit — the «крутится, когда ищет» spinner on
      // the recenter button must always END, success or not.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void listen(void Function(double lat, double lon, double? heading, double speedMps) onFix) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (p) => onFix(p.latitude, p.longitude, p.heading, p.speed),
      onError: (_) {},
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
