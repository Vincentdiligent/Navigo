/// Pure geo math: haversine, bearings, point-to-polyline projection.
library;

import 'dart:math' as math;

const double kEarthRadiusM = 6371008.8;

double deg2rad(double d) => d * math.pi / 180.0;
double rad2deg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in meters.
double distanceM(double lat1, double lon1, double lat2, double lon2) {
  final p1 = deg2rad(lat1), p2 = deg2rad(lat2);
  final dp = deg2rad(lat2 - lat1), dl = deg2rad(lon2 - lon1);
  final a =
      math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * kEarthRadiusM * math.asin(math.sqrt(a));
}

/// Initial bearing from point 1 to point 2, degrees [0, 360).
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = deg2rad(lat1), p2 = deg2rad(lat2);
  final dl = deg2rad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(p2);
  final x =
      math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (rad2deg(math.atan2(y, x)) + 360) % 360;
}

/// Result of projecting a point onto a polyline.
class Projection {
  const Projection({required this.index, required this.distanceM});
  final int index; // segment start vertex index
  final double distanceM; // meters from the polyline
}

/// Nearest segment of the polyline to the point.
Projection nearestOnPolyline(
  double lat,
  double lon,
  List<List<double>> line, // [[lat, lon], ...]
) {
  var best = const Projection(index: 0, distanceM: double.infinity);
  for (var i = 0; i + 1 < line.length; i++) {
    final d = _segmentDistance(lat, lon, line[i], line[i + 1]);
    if (d < best.distanceM) best = Projection(index: i, distanceM: d);
  }
  return best;
}

double _segmentDistance(
  double lat,
  double lon,
  List<double> a,
  List<double> b,
) {
  // Planar equirectangular approximation in meters around the midpoint —
  // accurate enough for off-route thresholds (< 1% error at city scale).
  final latR = deg2rad((a[0] + b[0]) / 2);
  final ax = deg2rad(a[1]) * math.cos(latR) * kEarthRadiusM;
  final ay = deg2rad(a[0]) * kEarthRadiusM;
  final bx = deg2rad(b[1]) * math.cos(latR) * kEarthRadiusM;
  final by = deg2rad(b[0]) * kEarthRadiusM;
  final px = deg2rad(lon) * math.cos(latR) * kEarthRadiusM;
  final py = deg2rad(lat) * kEarthRadiusM;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  var t = ((px - ax) * dx + (py - ay) * dy) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
}

/// Cuts a polyline: returns the remaining part starting at the vertex index
/// closest AFTER the projection point of (lat, lon).
List<List<double>> remainingAfter(
  double lat,
  double lon,
  List<List<double>> line,
) {
  if (line.length < 2) return line;
  final proj = nearestOnPolyline(lat, lon, line);
  final rest = line.sublist(proj.index + 1);
  return [
    <double>[lat, lon],
    ...rest,
  ];
}

/// Trim a polyline so it ends within [metersM] of walking/driving distance.
List<List<double>> trimToLength(List<List<double>> line, double metersM) {
  if (line.length < 2) return line;
  var acc = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    final d = distanceM(line[i][0], line[i][1], line[i + 1][0], line[i + 1][1]);
    if (acc + d >= metersM) {
      return line.sublist(0, i + 1);
    }
    acc += d;
  }
  return line;
}
