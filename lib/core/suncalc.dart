/// v5.8: sunrise / sunset — the engine behind «Ночная карта по закату».
/// Classic NOAA solar-position algorithm (the "Sunrise equation" from the
/// General Solar Position Calculations), no API, no package: date + lat/lon
/// in, UTC instants out. ±2 min accuracy is far beyond what an auto theme
/// switch needs.
library;

import 'dart:math' as math;

import 'geo_math.dart';

class SunTimes {
  const SunTimes({required this.sunriseUTC, required this.sunsetUTC});
  final DateTime sunriseUTC;
  final DateTime sunsetUTC;
}

SunTimes sunTimesUTC(DateTime date, double lat, double lon) {
  final d = date.toUtc();
  final dayAnchor = DateTime.utc(d.year, d.month, d.day);
  final n = d.difference(DateTime.utc(d.year, 1, 1)).inDays + 1;
  final lngHour = lon / 15.0;

  DateTime atHours(double ut) {
    var h = ut % 24;
    if (h < 0) h += 24;
    final hour = h.floor();
    final minute = ((h - hour) * 60).round();
    // 25.5 h after midnight = next day — DateTime handles the rollover.
    return dayAnchor.add(Duration(hours: hour, minutes: minute));
  }

  // Shared core for one event kind.
  double event(bool rise) {
    final t = n + (((rise ? 6 : 18) - lngHour) / 24);
    var m = 0.9856 * t - 3.289;
    final mrad = deg2rad(m);
    var l = m + 1.916 * math.sin(mrad) + 0.020 * math.sin(2 * mrad) + 282.634;
    l = l % 360;
    if (l < 0) l += 360;
    var ra = rad2deg(math.atan(0.91764 * math.tan(deg2rad(l))));
    ra = ra % 360;
    if (ra < 0) ra += 360;
    // Quadrant adjust so RA ends up in the same quadrant as L.
    final lq = (l / 90).floor() * 90;
    final raq = (ra / 90).floor() * 90;
    ra += lq - raq;
    final raHours = ra / 15;
    final sinDec = 0.39782 * math.sin(deg2rad(l));
    final cosDec = math.cos(math.asin(sinDec));
    const zenith = 90.833; // official sunrise/sunset
    final cosH =
        (math.cos(deg2rad(zenith)) - sinDec * math.sin(deg2rad(lat))) /
            (cosDec * math.cos(deg2rad(lat)));
    if (cosH > 1 || cosH < -1) {
      // Polar day / night: pin a stable fallback so the toggle still flips
      // at sane hours at extreme latitudes.
      return rise ? 4.5 : 20.5;
    }
    // Hour angle in DEGREES: sunrise is measured backwards (360 − H).
    var hDeg = rad2deg(math.acos(cosH));
    if (rise) hDeg = 360 - hDeg;
    final hHours = hDeg / 15;
    final tLocal = hHours + raHours - 0.06571 * t - 6.622;
    var ut = tLocal - lngHour;
    ut = ut % 24;
    if (ut < 0) ut += 24;
    return ut;
  }

  return SunTimes(
    sunriseUTC: atHours(event(true)),
    sunsetUTC: atHours(event(false)),
  );
}

/// True when the sun is below the horizon, with a soft [marginMin] window
/// around both events (the map dims slightly before it gets dark).
bool isNightNow(double lat, double lon, {int marginMin = 25, DateTime? now}) {
  final n = now ?? DateTime.now();
  final st = sunTimesUTC(n, lat, lon);
  final utc = n.toUtc();
  final dusk = st.sunsetUTC.add(Duration(minutes: marginMin));
  final dawn = st.sunriseUTC.subtract(Duration(minutes: marginMin));
  return utc.isAfter(dusk) || utc.isBefore(dawn);
}
