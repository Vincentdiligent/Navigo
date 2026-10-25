/// v5.7: transit (общественный транспорт) data model — pure data, no
/// imports, so both the AppState and the Transitous service can use it.
///
/// Source: Transitous (api.transitous.org) — a FREE, keyless community
/// router (MOTIS engine) aggregating official GTFS feeds worldwide; France
/// is covered by the official IDFM / RATP / SNCF / Transdev feeds (real
/// metro, RER, tram, bus line colors and delays included).
library;

/// Normalised GTFS mode.
enum TransitMode {
  walk,
  bus,
  subway,
  tram,
  rail,
  ferry,
  other,
}

/// One transfer point / intermediate stop.
class TransitStop {
  const TransitStop({
    required this.name,
    required this.lat,
    required this.lon,
    this.time,
  });
  final String name;
  final double lat, lon;
  final DateTime? time;
}

/// One leg of a transit itinerary: a walk segment or a ride on a line.
class TransitLeg {
  const TransitLeg({
    required this.mode,
    required this.fromName,
    required this.toName,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.depart,
    required this.arrive,
    required this.durationSec,
    required this.distanceM,
    required this.points,
    this.line = '',
    this.color = '',
    this.textColor = '',
    this.headsign = '',
    this.agency = '',
    this.realTime = false,
    this.stops = const [],
  });

  final TransitMode mode;
  final String fromName, toName;
  final double fromLat, fromLon, toLat, toLon;
  final DateTime depart, arrive;
  final int durationSec;
  final double distanceM;

  /// Decoded geometry, [lat, lon] pairs.
  final List<List<double>> points;

  /// Line short name («14», «C», «42», «RER A»…). Empty for walks.
  final String line;

  /// GTFS line colors ('#rrggbb'; may be '' → the UI falls back).
  final String color, textColor;

  /// Destination shown on the vehicle («Saint-Denis - Pleyel»).
  final String headsign;
  final String agency;
  final bool realTime;

  /// Board/intermediate/alight stops with times when available.
  final List<TransitStop> stops;

  bool get isWalk => mode == TransitMode.walk;
}

/// A complete door-to-door transit itinerary.
class TransitItinerary {
  const TransitItinerary({
    required this.depart,
    required this.arrive,
    required this.durationSec,
    required this.transfers,
    required this.legs,
  });

  final DateTime depart, arrive;
  final int durationSec;

  /// Number of VEHICLE changes (legs - 1 for rides).
  final int transfers;
  final List<TransitLeg> legs;

  double get meters {
    var s = 0.0;
    for (final l in legs) {
      s += l.distanceM;
    }
    return s;
  }

  int get walkSec {
    var s = 0;
    for (final l in legs) {
      if (l.isWalk) s += l.durationSec;
    }
    return s;
  }

  bool get hasRealTime => legs.any((l) => l.realTime);
}
