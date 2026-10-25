/// v5.7: transit follow session — rides along a [TransitItinerary] with the
/// user: tracks the current leg (GPS + schedule), announces transfers,
/// updates the HUD and fires arrival. Pure logic — strings live in the UI.
library;

import 'dart:async';

import '../core/geo_math.dart';
import 'transit_model.dart';

class TransitCallbacks {
  TransitCallbacks({
    required this.onLegChanged,
    required this.onApproachExit,
    required this.onProgress,
    required this.onArrive,
  });

  /// The rider boarded the leg at [index] (walk or vehicle).
  final void Function(int index) onLegChanged;

  /// The vehicle is approaching the exit stop of the current leg.
  final void Function(String stopName) onApproachExit;

  /// Distance to the next exit/transfer point, metres.
  final void Function(double remainM, int legIndex) onProgress;

  final void Function() onArrive;
}

class TransitSession {
  TransitSession(this._itinerary, this._callbacks);

  final TransitItinerary _itinerary;
  final TransitCallbacks _callbacks;

  int _leg = 0;
  bool _announcedExit = false;
  bool _arrived = false;
  Timer? _tick;

  TransitItinerary get itinerary => _itinerary;
  int get currentLeg => _leg;
  bool get arrived => _arrived;

  TransitLeg? get leg =>
      _leg >= 0 && _leg < _itinerary.legs.length ? _itinerary.legs[_leg] : null;

  /// Seconds until the final arrival (clamped ≥ 0).
  int remainSecToFinal() {
    final d = _itinerary.arrive.difference(DateTime.now().toUtc()).inSeconds;
    return d < 0 ? 0 : d;
  }

  /// Starts the schedule ticker (keeps guidance alive even with weak GPS —
  /// e.g. underground in the metro): re-evaluates the leg every 5 s.
  void start() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _evaluate());
  }

  /// Feed every GPS fix here.
  void onLocation(double lat, double lon) => _evaluate(lat, lon);

  void _evaluate([double? lat, double? lon]) {
    if (_arrived) return;
    final now = DateTime.now().toUtc();
    var moved = false;

    // Leg progression: a leg is DONE when the rider is physically near its
    // endpoint, or (no GPS in the tunnel) the schedule moved past it by
    // more than 45 s.
    while (_leg < _itinerary.legs.length - 1) {
      final leg = _itinerary.legs[_leg];
      final nearEnd =
          lat != null && distanceM(lat, lon!, leg.toLat, leg.toLon) < 32;
      final passed = now.isAfter(leg.arrive.toUtc().add(
        const Duration(seconds: 45),
      ));
      if (nearEnd || passed) {
        _leg++;
        moved = true;
        _announcedExit = false;
        continue;
      }
      break;
    }
    if (moved) {
      _callbacks.onLegChanged(_leg);
    }

    final leg = this.leg;
    if (leg == null) return;

    // Distance to the next exit / transfer point.
    final remainM = (lat != null)
        ? distanceM(lat, lon!, leg.toLat, leg.toLon)
        : leg.distanceM;
    _callbacks.onProgress(remainM, _leg);

    // «Выходите на следующей» — one announcement per leg.
    if (!_announcedExit && !leg.isWalk && remainM < 140) {
      _announcedExit = true;
      _callbacks.onApproachExit(leg.toName);
    }

    // Arrival: near the final endpoint or the schedule is done.
    final last = _itinerary.legs.last;
    final nearFinal =
        lat != null && distanceM(lat, lon!, last.toLat, last.toLon) < 30;
    if (nearFinal || now.isAfter(_itinerary.arrive.toUtc().add(const Duration(seconds: 60)))) {
      _arrived = true;
      _callbacks.onArrive();
    }
  }

  void dispose() {
    _tick?.cancel();
  }
}
