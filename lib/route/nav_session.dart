/// Navigation session: follow mode, progress slicing, off-route recovery,
/// spoken instructions and arrival detection.
library;

import 'dart:async';

import '../core/app_state.dart';
import '../core/geo_math.dart';
import 'route_service.dart';

class NavCallbacks {
  NavCallbacks({
    required this.onProgress,
    required this.onAnnounce,
    required this.onReroute,
    required this.onArrive,
  });
  final void Function(double remainM, double remainS, List<List<double>> traveled)
      onProgress;
  final void Function(String text) onAnnounce;
  final void Function() onReroute;
  final void Function() onArrive;
}

class NavSession {
  NavSession(this._route, this._mode, this._callbacks, {this.offRouteM = 45});

  final LuxRoute _route;
  final TravelMode _mode;
  final NavCallbacks _callbacks;
  final double offRouteM;

  double remainM = 0;
  double remainS = 0;
  bool _announcedFar = false;
  bool _announcedNear = false;
  int _lastStepIndex = -1;
  Timer? _recalcGuard;

  LuxRoute get route => _route;
  RouteStep? get currentStep {
    if (_route.steps.isEmpty) return null;
    final i = _lastStepIndex.clamp(0, _route.steps.length - 1);
    return _route.steps[i];
  }

  /// Feed every GPS fix here.
  void onLocation(double lat, double lon, double speedMps) {
    final proj = nearestOnPolyline(lat, lon, _route.line);
    if (proj.distanceM > offRouteM) {
      // Debounce: one reroute request per 10 s.
      _recalcGuard ??= Timer(const Duration(seconds: 10), () {
        _recalcGuard = null;
      });
      if (_recalcGuard!.isActive) {
        _callbacks.onReroute();
      }
      return;
    }
    final traveled = _route.line.sublist(0, proj.index + 1);
    final traveledM = _lengthM(traveled);
    remainM = (_route.meters - traveledM).clamp(0, _route.meters);
    final speed = speedMps > 0.7 ? speedMps : _cruiseSpeed();
    remainS = remainM / speed;
    _callbacks.onProgress(remainM, remainS, traveled);

    _speakGuidance(lat, lon, speed);
    if (remainM < 28) {
      _callbacks.onArrive();
    }
  }

  double _cruiseSpeed() => switch (_mode) {
        TravelMode.car => 12.5,
        TravelMode.bike => 4.4,
        TravelMode.foot => 1.35,
        // Unused (transit guidance runs in TransitSession) — but legal.
        TravelMode.transit => 1.35,
      };

  double _lengthM(List<List<double>> line) {
    var s = 0.0;
    for (var i = 0; i + 1 < line.length; i++) {
      s += distanceM(line[i][0], line[i][1], line[i + 1][0], line[i + 1][1]);
    }
    return s;
  }

  void _speakGuidance(double lat, double lon, double speed) {
    if (_route.steps.isEmpty) return;
    // Distance to the NEXT step (first step whose location is still ahead).
    for (var i = 0; i < _route.steps.length; i++) {
      final st = _route.steps[i];
      final d = distanceM(lat, lon, st.lat, st.lon);
      if (d < 1) continue;
      final farThreshold = speed > 8 ? 320.0 : 110.0;
      if (!_announcedFar && d < farThreshold && d > 30) {
        _announcedFar = true;
        _lastStepIndex = i;
        _callbacks.onAnnounce(_textFor(st));
        return;
      }
      if (!_announcedNear && d < 45) {
        _announcedNear = true;
        _lastStepIndex = i;
        _callbacks.onAnnounce(_textFor(st));
        return;
      }
      if (d < 18 && i > _lastStepIndex) {
        _lastStepIndex = i;
        _announcedFar = false;
        _announcedNear = false;
      }
      // Only care about the first upcoming step.
      break;
    }
  }

  String _textFor(RouteStep st) {
    // Locale-neutral: the UI layer maps maneuver keys to strings; here we
    // pass a compact key + street so TTS speaks the caller's language.
    return st.key;
  }

  /// Ready-to-speak sentence (used by the voice wrapper).
  static String sentence({
    required String maneuverText,
    required String street,
    required String onWord,
  }) {
    if (street.isEmpty) return maneuverText;
    return '$maneuverText $onWord $street';
  }

  void dispose() {
    _recalcGuard?.cancel();
  }
}
