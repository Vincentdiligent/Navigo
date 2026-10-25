/// Route preview card + navigation HUD (single surface family).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../route/maneuver_text.dart';
import '../route/speed_cameras.dart' show CamAlert;
import '../route/transit_model.dart';
import 'widgets.dart';

/// Icon per transit mode (GTFS normalised).
IconData transitModeIcon(TransitMode m) => switch (m) {
      TransitMode.walk => Icons.directions_walk_rounded,
      TransitMode.bus => Icons.directions_bus_rounded,
      TransitMode.subway => Icons.directions_subway_rounded,
      TransitMode.tram => Icons.tram_rounded,
      TransitMode.rail => Icons.train_rounded,
      TransitMode.ferry => Icons.directions_boat_rounded,
      TransitMode.other => Icons.directions_transit_rounded,
    };

/// Local HH:mm for a UTC itinerary timestamp.
String _hm(DateTime utc) {
  final l = utc.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Small mode selector used inside the panels. v5.7 adds the TRANSIT
/// profile (общественный транспорт).
class ModeRow extends StatelessWidget {
  const ModeRow({super.key, required this.mode, required this.onPick});
  final TravelMode mode;
  final ValueChanged<TravelMode> onPick;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    Widget chip(TravelMode m, IconData icon, String label) {
      final active = m == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onPick(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 40,
            decoration: BoxDecoration(
              color: active ? t.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? t.onPrimary : t.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? t.onPrimary : t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          chip(TravelMode.car, Icons.directions_car_rounded, S.of('car')),
          chip(TravelMode.bike, Icons.directions_bike_rounded, S.of('bike')),
          chip(TravelMode.foot, Icons.directions_walk_rounded, S.of('foot')),
          chip(
            TravelMode.transit,
            Icons.directions_transit_rounded,
            S.of('transitShort'),
          ),
        ],
      ),
    );
  }
}

class RoutePreviewCard extends StatelessWidget {
  const RoutePreviewCard({
    super.key,
    required this.state,
    required this.onStart,
    required this.onClose,
    required this.onModeChanged,
    this.canStart = true,
    this.onPickAlt,
  });

  final AppState state;
  final VoidCallback onStart;
  final VoidCallback onClose;
  final ValueChanged<TravelMode> onModeChanged;

  /// v5.3: false when the route starts at a planner-chosen point that is
  /// far from the device — the preview is shown, guidance is not offered.
  final bool canStart;

  /// v5.5: switch to another route variant (fastest / shorter…).
  final ValueChanged<int>? onPickAlt;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.route_rounded, color: t.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // v5.3: the start line — «Откуда → Куда». The device
                    // location collapses into a short label.
                    Text(
                      state.routeOrigin == null
                          ? '${S.of('myLocation')} → ${state.destination?.name ?? ''}'
                          : '${state.routeOrigin!.name} → ${state.destination?.name ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      state.destination?.name ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.formatDistance(state.routeMeters)}'
                      ' · ${state.formatDuration(state.routeSeconds)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: t.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          ModeRow(mode: state.mode, onPick: onModeChanged),

          // ── v5.5: route variants («быстрее / короче») ───────────────
          if (state.routeAlts.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.routeAlts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _AltChip(
                  alt: state.routeAlts[i],
                  index: i,
                  selected: i == state.selectedAlt,
                  onTap: () => onPickAlt?.call(i),
                ),
              ),
            ),
          ],

          // ── v5.5: badges (платные / магистрали / паромы) + работы ───
          if (_badgeCount(state) > 0 || state.incidentsCount != 0) ...[
            const SizedBox(height: 8),
            _BadgesRow(state: state),
          ],

          const SizedBox(height: 12),
          if (canStart)
            PrimaryButton(
              label: S.of('start'),
              icon: Icons.navigation_rounded,
              onTap: onStart,
            )
          else
            // Preview-only route: the start is elsewhere (planner).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.outline.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: t.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      S.of('previewOnly'),
                      style: TextStyle(fontSize: 13, color: t.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static int _badgeCount(AppState state) {
    final alts = state.routeAlts;
    if (state.selectedAlt >= alts.length) return 0;
    final a = alts[state.selectedAlt];
    var n = 0;
    if (a.hasToll) n++;
    if (a.hasHighway) n++;
    if (a.hasFerry) n++;
    return n;
  }
}

/// v5.5: one selectable route variant chip — «Быстрый · 24 мин · 32 км».
class _AltChip extends StatelessWidget {
  const _AltChip({
    required this.alt,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final RouteAlt alt;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.read<AppState>();
    final label = alt.label == 'short'
        ? S.of('altShortest')
        : alt.label == 'tollFree'
            ? S.of('altTollFree')
            : S.of('altFastest');
    return Material(
      color: selected ? t.primary.withValues(alpha: 0.16) : t.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? t.primary : t.outline.withValues(alpha: 0.5),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                alt.label == 'short'
                    ? Icons.straighten_rounded
                    : Icons.bolt_rounded,
                size: 17,
                color: selected ? t.primary : t.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '$label · ${state.formatDuration(alt.seconds)} · '
                '${state.formatDistance(alt.meters)}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? t.primary : t.onBackground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v5.5: badges row — route traits (платные / магистрали / паромы) +
/// roadworks found on the way (OpenStreetMap).
class _BadgesRow extends StatelessWidget {
  const _BadgesRow({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final alts = state.routeAlts;
    final a = state.selectedAlt < alts.length ? alts[state.selectedAlt] : null;
    final chips = <Widget>[
      if (a != null && a.hasToll)
        _badge(Icons.currency_ruble_rounded, S.of('badgeToll'),
            Colors.deepOrange.shade400),
      if (a != null && a.hasHighway)
        _badge(Icons.speed_rounded, S.of('badgeHighway'),
            Colors.blueGrey.shade400),
      if (a != null && a.hasFerry)
        _badge(Icons.directions_boat_rounded, S.of('badgeFerry'),
            Colors.teal.shade300),
      if (state.incidentsCount == -1)
        _badge(
          Icons.more_horiz_rounded,
          S.of('incidentsChecking'),
          t.textMuted,
        ),
      if (state.incidentsCount > 0)
        _badge(
          Icons.construction_rounded,
          '${S.of('incidentsWorks')}: ${state.incidentsCount}',
          const Color(0xFFC77700),
        ),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Big maneuver glyph for the HUD.
IconData maneuverIcon(String key) {
  final mod = key.split('|').length > 1 ? key.split('|')[1] : '';
  if (key.startsWith('roundabout')) return Icons.roundabout_right_rounded;
  if (key.startsWith('merge')) return Icons.merge_rounded;
  if (key.startsWith('fork')) {
    return mod.contains('left')
        ? Icons.alt_route_rounded
        : Icons.alt_route_rounded;
  }
  if (key.startsWith('exit')) return Icons.exit_to_app_rounded;
  return switch (mod) {
    'left' => Icons.turn_left_rounded,
    'right' => Icons.turn_right_rounded,
    'sharp left' => Icons.turn_slight_left_rounded,
    'sharp right' => Icons.turn_slight_right_rounded,
    'slight left' => Icons.turn_slight_left_rounded,
    'slight right' => Icons.turn_slight_right_rounded,
    'uturn' => Icons.u_turn_left_rounded,
    _ => Icons.arrow_upward_rounded,
  };
}

/// v5.9: THE TOP NAV STRIP. While guidance runs the search field shrinks
/// into a small round button on the left, and the km + arrival info move
/// UP HERE («сверху поле поиска укарачивалось в круг маленький слево а
/// туда перемещалось и км и инфа»):
///   [X круглая] [КРУГЛЫЙ бейдж с км] [прибытие · осталось] [звук] [обзор]
class NavTopBar extends StatelessWidget {
  const NavTopBar({
    super.key,
    required this.state,
    required this.onStop,
    required this.onOverview,
    required this.onToggleSound,
    this.overviewActive = false,
  });

  final AppState state;
  final VoidCallback onStop;
  final VoidCallback onOverview;
  final VoidCallback onToggleSound;
  final bool overviewActive;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    // The ROUND distance badge («прямоугольный макет убери и сделай его
    // круглый как другие кнопки и там помести расстояние!»).
    final km = state.remainingMeters;
    final String distValue;
    final String distUnit;
    if (km >= 1000) {
      distValue = (km / 1000).toStringAsFixed(km >= 10000 ? 0 : 1);
      distUnit = S.of('km');
    } else {
      distValue = '${km.round()}';
      distUnit = S.of('m');
    }
    final eta = DateTime.now()
        .add(Duration(seconds: state.remainingSeconds.round()));
    final hh =
        '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        RoundFab(
          icon: Icons.close_rounded,
          tooltip: S.of('stop'),
          size: 46,
          onTap: onStop,
        ),
        const SizedBox(width: 8),
        _DistBadge(value: distValue, unit: distUnit),
        const SizedBox(width: 8),
        Expanded(
          child: _GlassPill(
            child: Row(
              children: [
                Icon(Icons.flag_rounded, size: 15, color: t.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$hh · ${state.formatDuration(state.remainingSeconds)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        RoundFab(
          icon: state.voiceOn
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          tooltip: S.of('sound'),
          active: state.voiceOn,
          size: 46,
          onTap: onToggleSound,
        ),
        const SizedBox(width: 8),
        RoundFab(
          icon: overviewActive
              ? Icons.near_me_rounded
              : Icons.map_rounded,
          tooltip: overviewActive
              ? S.of('followMe')
              : S.of('overview'),
          active: overviewActive,
          size: 46,
          onTap: onOverview,
        ),
      ],
    );
  }
}

/// v5.9: the round distance badge — same circle language as every other
/// map button, primary accent, distance + unit stacked inside.
class _DistBadge extends StatelessWidget {
  const _DistBadge({required this.value, required this.unit});
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: t.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: t.onPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: t.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// v5.9: neutral glass pill (arrival info) matching the round buttons.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.isDark ? t.surface.withValues(alpha: 0.96) : t.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: t.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// v5.9: the REAL bottom sheet frame for navigation — full width, big 28
/// top radius, a drag handle; drag up expands, drag down collapses. The
/// user: «внизу надо чтобы реальный sheets окно было … не нравится окна
/// квадратные с полукруглыми углами».
class _NavSheetFrame extends StatefulWidget {
  const _NavSheetFrame({required this.builder});

  /// Builds the sheet content for the current expansion state.
  final Widget Function(BuildContext context, bool expanded) builder;

  @override
  State<_NavSheetFrame> createState() => _NavSheetFrameState();
}

class _NavSheetFrameState extends State<_NavSheetFrame> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.isDark ? t.surface.withValues(alpha: 0.98) : t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: t.outline.withValues(alpha: 0.8)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The handle: tap toggles, drag up/down expands/collapses.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -60 && !_expanded) _toggle();
              if (v > 60 && _expanded) _toggle();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: _expanded ? 34 : 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: t.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: widget.builder(context, _expanded),
          ),
          SizedBox(height: bottomPad > 0 ? bottomPad : 8),
        ],
      ),
    );
  }
}

class NavHud extends StatefulWidget {
  const NavHud({
    super.key,
    required this.state,
    required this.onStop,
    this.onOverview,
    this.overviewActive = false,
  });
  final AppState state;
  final VoidCallback onStop;

  /// v5.7: «нужен маршрут отдельно чтобы посмотреть» — zoom out to the
  /// whole route (second tap returns to the follow camera).
  final VoidCallback? onOverview;
  final bool overviewActive;

  @override
  State<NavHud> createState() => _NavHudState();
}

/// v5.9 DRIVING SHEET — the old half-screen card is gone. Everything
/// important lives in a slim real sheet at the very bottom:
///   collapsed: [LIMIT 90] [◉ 64] [↑] Поверните направо · через 250 м
///              ▓▓▓▓▓▓░░░ route progress
///   expanded:  + В пути 12 мин · Прибытие 14:35  [Обзор] [Завершить]
/// The km + arrival info moved to the TOP strip ([NavTopBar]); the speed
/// cluster, the maneuver and the stop live here, never covering the map.
/// The 1-second ticker keeps the arrival clock live without AppState.
class _NavHudState extends State<NavHud> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // arrival clock
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed(AppState st) {
    final start = st.navStartedAt;
    if (start == null) return '0 ${S.of('min')}';
    final d = DateTime.now().difference(start);
    final m = d.inMinutes;
    if (m < 60) return '$m ${S.of('min')}';
    return '${m ~/ 60} ${S.of('h')} ${(m % 60).toString().padLeft(2, '0')}';
  }

  String _arrivalAt(AppState st) {
    final eta = DateTime.now().add(
      Duration(seconds: st.remainingSeconds.round()),
    );
    return '${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}';
  }

  String _nextLine(AppState state) {
    final d = state.formatDistance(state.maneuverDistanceM);
    final street = state.maneuverStreet;
    return street.isEmpty
        ? '${S.of('manIn')} $d'
        : '${S.of('manIn')} $d · $street';
  }

  @override
  Widget build(BuildContext context) {
    return _NavSheetFrame(
      builder: (context, expanded) => _body(context, expanded),
    );
  }

  Widget _body(BuildContext context, bool expanded) {
    final t = luxThemeOf(context);
    final state = widget.state;
    final rerouting = state.navPhase == NavPhase.rerouting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The CAMERA chip — appears above the driving row while a fixed
          // camera is ahead (v5.8 behavior, compact v5.9 placement).
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: state.camAlert == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CamChip(alert: state.camAlert!),
                  ),
          ),
          Row(
            children: [
              _SpeedLimitBadge(state: state),
              const SizedBox(width: 8),
              _SpeedDial(state: state),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  maneuverIcon(state.currentManeuver),
                  color: t.onPrimary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rerouting
                          ? S.of('rerouting')
                          : maneuverTitle(state.currentManeuver),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      rerouting
                          ? state.formatDistance(state.routeMeters)
                          : _nextLine(state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Route progress line.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: state.routeMeters <= 0
                    ? 0
                    : 1 - state.remainingMeters / state.routeMeters,
              ),
              duration: const Duration(milliseconds: 300),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v.clamp(0, 1),
                minHeight: 5,
                backgroundColor: t.surfaceAlt,
                color: t.primary,
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    icon: Icons.schedule_rounded,
                    label: S.of('elapsed'),
                    value: _elapsed(state),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.flag_rounded,
                    label: S.of('arrivalAt'),
                    value: _arrivalAt(state),
                  ),
                ),
              ],
            ),
            if (widget.onOverview != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _HudRoundBtn(
                    icon: widget.overviewActive
                        ? Icons.near_me_rounded
                        : Icons.map_rounded,
                    tooltip: widget.overviewActive
                        ? S.of('followMe')
                        : S.of('overview'),
                    onTap: widget.onOverview!,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: t.outline,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: widget.onStop,
                        child: Text(S.of('stop')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// v5.9: the SPEED DIAL — a round dark circle (Google-Maps-like) with the
/// live GPS speed; the whole dial turns red while over the limit. The old
/// rectangular box is gone («бейджик прямоугольный мешает»).
class _SpeedDial extends StatelessWidget {
  const _SpeedDial({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final over = state.isOverspeed;
    final bg = over
        ? const Color(0xFFD93025)
        : (t.isDark ? const Color(0xFF2A2C31) : const Color(0xFF202124));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: over
            ? Border.all(color: const Color(0xFFB3261C), width: 2)
            : Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: over
                ? const Color(0xFFD93025).withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            state.speedKmh.round().clamp(0, 255).toString(),
            style: TextStyle(
              fontSize: 17,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            S.of('kmh'),
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

/// v5.8: the Google-Maps-style speed-limit sign. White plate + black number
/// while legal; red plate + white number + pulse while over the limit
/// («если дорога 90 а я еду выше нормы то индикатор как-то загорелся»).
class _SpeedLimitBadge extends StatefulWidget {
  const _SpeedLimitBadge({required this.state});
  final AppState state;

  @override
  State<_SpeedLimitBadge> createState() => _SpeedLimitBadgeState();
}

class _SpeedLimitBadgeState extends State<_SpeedLimitBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final lim = state.speedLimitKmh;
    // Hide when stale (> 40 s without a fresh road match).
    final stale =
        DateTime.now().difference(state.speedLimitAt).inSeconds > 40;
    final show = lim != null && !stale;
    final over = state.isOverspeed;
    if (over && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!over && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 240),
      opacity: show ? 1 : 0,
      child: ScaleTransition(
        scale: over
            ? Tween(begin: 1.0, end: 1.09).animate(
                CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
              )
            : const AlwaysStoppedAnimation(1.0),
        child: Container(
          width: 52,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: over ? const Color(0xFFD93025) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: over ? const Color(0xFFB3261C) : const Color(0xFF9AA0A6),
              width: over ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            '${lim ?? 0}',
            style: TextStyle(
              fontSize: 21,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: over ? Colors.white : const Color(0xFF17181A),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// v5.8: camera-approach chip. Amber while far, pulsing red under 150 m —
/// «предупреждения по камерам … как это сделано в google maps».
class _CamChip extends StatelessWidget {
  const _CamChip({required this.alert});
  final CamAlert alert;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final t = luxThemeOf(context);
    final near = alert.close;
    final accent = near ? const Color(0xFFD93025) : const Color(0xFFB77700);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.97, end: near ? 1.03 : 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: near ? 0.16 : 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: [
            Icon(Icons.photo_camera_rounded, size: 17, color: accent),
            const SizedBox(width: 8),
            Text(
              S.of('camChip'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${alert.cam.maxspeed != null ? '· ${alert.cam.maxspeed} ${S.of('kmh')} ' : ''}'
                '· ${st.formatDistance(alert.distanceM)}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.onBackground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small labelled stat inside the HUD info strip.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: t.textMuted),
        const SizedBox(width: 5),
        Text(
          '$label · ',
          style: TextStyle(fontSize: 11.5, color: t.textMuted),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// v5.8: PREMIUM ARRIVAL SUMMARY — the user gets a real trip report instead
/// of a bare «Вы прибыли»: animated check, destination, three stats (time /
/// distance / average speed) and Save / Share / Done actions.
class ArrivalSummaryCard extends StatelessWidget {
  const ArrivalSummaryCard({
    super.key,
    required this.state,
    required this.onClose,
    this.onSave,
    this.onShare,
  });

  final AppState state;
  final VoidCallback onClose;
  final VoidCallback? onSave;
  final VoidCallback? onShare;

  String _avg(AppState st) {
    if (st.tripSeconds < 5) return '—';
    final kmh = st.tripMeters / st.tripSeconds * 3.6;
    return '${kmh.round()} ${S.of('kmh')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.35, end: 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (context, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22A35F),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of('arrived'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      state.destination?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ArrivalStat(
                  icon: Icons.schedule_rounded,
                  label: S.of('tripDuration'),
                  value: state.formatDuration(state.tripSeconds),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ArrivalStat(
                  icon: Icons.straighten_rounded,
                  label: S.of('tripDistance'),
                  value: state.formatDistance(state.tripMeters),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ArrivalStat(
                  icon: Icons.speed_rounded,
                  label: S.of('avgSpeed'),
                  value: _avg(state),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onSave != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: onSave,
                    icon: const Icon(Icons.star_rounded, size: 19),
                    label: Text(S.of('savePlace')),
                  ),
                ),
              if (onSave != null) const SizedBox(width: 8),
              if (onShare != null)
                _HudRoundBtn(
                  icon: Icons.share_rounded,
                  tooltip: S.of('share'),
                  onTap: onShare!,
                ),
              if (onShare != null) const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.onPrimary,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onClose,
                  child: Text(S.of('done')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One stat tile of the arrival card.
class _ArrivalStat extends StatelessWidget {
  const _ArrivalStat({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.outline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: t.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// v5.7: compact round button inside the HUD row (overview toggle).
class _HudRoundBtn extends StatelessWidget {
  const _HudRoundBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 21, color: t.onBackground),
          ),
        ),
      ),
    );
  }
}

/// v5.7: THE TRANSIT PREVIEW — list of departure options with the colored
/// leg strip (official GTFS line colors), then the chosen itinerary's legs
/// with departure times. Premium, keyless, worldwide (Transitous).
class TransitPreviewCard extends StatelessWidget {
  const TransitPreviewCard({
    super.key,
    required this.state,
    required this.onStart,
    required this.onClose,
    required this.onPick,
    required this.onModeChanged,
  });

  final AppState state;
  final VoidCallback onStart;
  final VoidCallback onClose;
  final ValueChanged<int> onPick;
  final ValueChanged<TravelMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final plan = state.transitPlan;
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.directions_transit_rounded,
                  color: t.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${state.destination?.name ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      S.of('transitSub'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),
          ModeRow(mode: state.mode, onPick: onModeChanged),
          const SizedBox(height: 10),

          // Departure options.
          if (state.transitOptions.length > 1)
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: state.transitOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _TransitOptionChip(
                  it: state.transitOptions[i],
                  selected: plan != null && identical(plan, state.transitOptions[i]),
                  onTap: () => onPick(i),
                ),
              ),
            ),
          const SizedBox(height: 10),

          // Leg strip of the selected itinerary.
          if (plan != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '${_hm(plan.depart)} → ${_hm(plan.arrive)}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        state.formatDuration(plan.durationSec.toDouble()),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        plan.transfers <= 0
                            ? S.of('transfersZero')
                            : '${plan.transfers} ${S.of('transferCount')}',
                        style: TextStyle(fontSize: 12, color: t.textMuted),
                      ),
                      if (plan.hasRealTime) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22B573)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            S.of('transitLiveOk'),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF17905A),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 30,
                    child: Row(
                      children: [
                        for (var i = 0; i < plan.legs.length; i++)
                          Expanded(child: _LegStripSegment(leg: plan.legs[i])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Legs detail (max height with scroll).
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 196),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final leg in plan.legs)
                      _TransitLegRow(leg: leg, state: state),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),
          PrimaryButton(
            label: S.of('transitStart'),
            icon: Icons.play_arrow_rounded,
            onTap: onStart,
          ),
        ],
      ),
    );
  }
}

/// One departure option chip: «14:47 → 15:13 · 26 мин · 1 пересадка».
class _TransitOptionChip extends StatelessWidget {
  const _TransitOptionChip({
    required this.it,
    required this.selected,
    required this.onTap,
  });
  final TransitItinerary it;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.read<AppState>();
    return Material(
      color: selected ? t.primary.withValues(alpha: 0.16) : t.surfaceAlt,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? t.primary : t.outline.withValues(alpha: 0.5),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final leg in it.legs.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    transitModeIcon(leg.mode),
                    size: 14,
                    color: leg.isWalk ? t.textMuted : _legColor(leg),
                  ),
                ),
              const SizedBox(width: 2),
              Text(
                '${_hm(it.depart)} · ${state.formatDuration(it.durationSec.toDouble())}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? t.primary : t.onBackground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _legColor(TransitLeg leg) {
  final c = leg.color;
  if (c.length >= 7) {
    try {
      return Color(int.parse(c.substring(1), radix: 16) | 0xFF000000);
    } catch (_) {}
  }
  return const Color(0xFF5C7FA3);
}

/// Proportional strip segment: walk = dashed neutral, ride = line color.
class _LegStripSegment extends StatelessWidget {
  const _LegStripSegment({required this.leg});
  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.5),
      child: LayoutBuilder(
        builder: (context, box) {
          if (leg.isWalk) {
            return CustomPaint(
              size: Size(box.maxWidth, 30),
              painter: _DashedLinePainter(
                color: t.textMuted.withValues(alpha: 0.8),
              ),
            );
          }
          return Container(
            height: 10,
            decoration: BoxDecoration(
              color: _legColor(leg),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              leg.line,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: _legTextColor(leg),
                height: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}

Color _legTextColor(TransitLeg leg) {
  final c = leg.textColor;
  if (c.length >= 7) {
    try {
      return Color(int.parse(c.substring(1), radix: 16) | 0xFF000000);
    } catch (_) {}
  }
  return Colors.white;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 4.0, gap = 4.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

/// One leg row in the detail list.
class _TransitLegRow extends StatelessWidget {
  const _TransitLegRow({required this.leg, required this.state});
  final TransitLeg leg;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    if (leg.isWalk) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(transitModeIcon(leg.mode), size: 16, color: t.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${S.of('walkTo')} «${leg.toName}»'
                ' · ${state.formatDuration(leg.durationSec.toDouble())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: t.textMuted),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 22,
            decoration: BoxDecoration(
              color: _legColor(leg),
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text(
              leg.line,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _legTextColor(leg),
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${_hm(leg.depart)} · ${leg.fromName.isEmpty ? leg.headsign : leg.fromName}'
              ' → ${leg.toName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.onBackground,
              ),
            ),
          ),
          Text(
            leg.stops.isEmpty
                ? state.formatDuration(leg.durationSec.toDouble())
                : '${leg.stops.length} · ${state.formatDuration(leg.durationSec.toDouble())}',
            style: TextStyle(fontSize: 11.5, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

/// v5.7: THE TRANSIT HUD while riding the chosen itinerary.
class TransitHud extends StatelessWidget {
  const TransitHud({
    super.key,
    required this.state,
    required this.onStop,
    this.onOverview,
    this.overviewActive = false,
  });

  final AppState state;
  final VoidCallback onStop;
  final VoidCallback? onOverview;
  final bool overviewActive;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final plan = state.transitPlan;
    if (plan == null) return const SizedBox.shrink();
    final legIdx = state.transitLeg.clamp(0, plan.legs.length - 1);
    final leg = plan.legs[legIdx];
    final isWalk = leg.isWalk;
    final accent = isWalk ? t.primary : _legColor(leg);

    // v5.9: the transit ride lives in the same REAL sheet as the car HUD —
    // slim collapsed row (line + «Выходите…» + ETA), expandable to the
    // trip progress + stop. Nothing covers half the screen anymore.
    return _NavSheetFrame(
      builder: (context, expanded) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Line badge (or walk glyph).
                Container(
                  width: 48,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: isWalk
                      ? Icon(
                          Icons.directions_walk_rounded,
                          color: t.onPrimary,
                          size: 22,
                        )
                      : Text(
                          leg.line,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _legTextColor(leg),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isWalk
                            ? '${S.of('walkTo')} «${leg.toName}»'
                            : '${S.of('exitAt')} «${leg.toName}»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: t.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        leg.headsign.isEmpty ? leg.fromName : leg.headsign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      S.of('eta'),
                      style: TextStyle(fontSize: 10.5, color: t.textMuted),
                    ),
                    Text(
                      state.formatDuration(
                        plan.arrive
                            .difference(DateTime.now())
                            .inSeconds
                            .clamp(0, 24 * 3600)
                            .toDouble(),
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              // Whole-trip progress: rider position = elapsed / total.
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                    begin: 0,
                    end: plan.durationSec <= 0
                        ? 0
                        : 1 -
                            plan.arrive
                                    .difference(DateTime.now())
                                    .inSeconds /
                                plan.durationSec,
                  ),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: t.surfaceAlt,
                    color: t.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onOverview != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _HudRoundBtn(
                        icon: overviewActive
                            ? Icons.near_me_rounded
                            : Icons.map_rounded,
                        tooltip: overviewActive
                            ? S.of('followMe')
                            : S.of('overview'),
                        onTap: onOverview!,
                      ),
                    ),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: t.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: onStop,
                        child: Text(S.of('stop')),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
