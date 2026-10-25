/// Route planner sheet (v5.6 → v5.8): «Откуда → Куда» with INLINE, TYPEABLE
/// endpoint fields, live address suggestions, a device-location start,
/// one-tap SWAP of the endpoints, the travel-mode row — and, new in v5.8,
/// INTERMEDIATE STOPS (A → B → C → D, the user approved «промежуточные
/// точки») plus RECENT destinations chips (история поездок).
///
/// The result is a [RoutePlan]: [RoutePlan.fromDevice] = start at the device
/// location, otherwise an explicit start place. [RoutePlan.stops] carries
/// the intermediates. The caller fetches and draws the route — the sheet
/// never touches the map.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../places/geocoding.dart';
import 'route_panel.dart';
import 'widgets.dart';

/// A resolved A→B request (with optional intermediates).
class RoutePlan {
  const RoutePlan.device(this.to, {this.stops = const []}) : from = null;
  const RoutePlan({this.from, required this.to, this.stops = const []});

  /// null → start from the device location.
  final LuxPlace? from;
  final LuxPlace to;

  /// v5.8: intermediate stops in order (max 3).
  final List<LuxPlace> stops;
}

Future<RoutePlan?> showRoutePlanner(
  BuildContext context, {
  LuxPlace? from,
  LuxPlace? to,
}) => showLuxSheet(
  context: context,
  tag: 'planner',
  builder: (_) => _PlannerSheet(from: from, to: to),
);

/// Per-field controller bundle — one for FROM, one for TO, one per stop.
class _FieldCtl {
  final TextEditingController ctrl = TextEditingController();
  final FocusNode focus = FocusNode();
  LuxPlace? place;
  List<LuxPlace> sug = const [];
  bool busy = false;
  Timer? debounce;
  int token = 0;

  void dispose() {
    ctrl.dispose();
    focus.dispose();
    debounce?.cancel();
  }
}

class _PlannerSheet extends StatefulWidget {
  const _PlannerSheet({this.from, this.to});

  final LuxPlace? from;
  final LuxPlace? to;

  @override
  State<_PlannerSheet> createState() => _PlannerSheetState();
}

class _PlannerSheetState extends State<_PlannerSheet> {
  final Geocoding _geo = Geocoding();

  late final _FieldCtl _from = _FieldCtl();
  late final _FieldCtl _to = _FieldCtl();
  final List<_FieldCtl> _stops = [];

  static const int _maxStops = 3;

  @override
  void initState() {
    super.initState();
    _from.place = widget.from;
    _to.place = widget.to;
    _from.ctrl.text = widget.from?.name ?? '';
    _to.ctrl.text = widget.to?.name ?? '';
    // A prefilled destination → start editing the start point; otherwise
    // put the cursor straight into the destination field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.to != null) {
        _from.focus.requestFocus();
      } else {
        _to.focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  // ── typing → live suggestions ───────────────────────────────────────
  void _onChanged(_FieldCtl f, String q) {
    if (f.place != null && q.trim() != f.place!.name) f.place = null;
    if (q.trim().isEmpty) {
      f.token++;
      setState(() {
        f.sug = const [];
        f.busy = false;
      });
      return;
    }
    f.debounce?.cancel();
    f.debounce = Timer(const Duration(milliseconds: 500), () => _search(f, q));
  }

  Future<void> _search(_FieldCtl f, String q) async {
    final token = ++f.token;
    setState(() => f.busy = true);
    try {
      final res = await _geo.suggest(q, near: _anchor(), language: _lang());
      if (!mounted || token != f.token) return;
      setState(() {
        f.sug = res.take(6).toList();
        f.busy = false;
      });
    } catch (_) {
      if (!mounted || token != f.token) return;
      setState(() => f.busy = false);
    }
  }

  void _pick(_FieldCtl f, LuxPlace p) {
    setState(() {
      f.place = p;
      f.ctrl.text = p.name;
      f.sug = const [];
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ── v5.8: intermediate stops ────────────────────────────────────────
  void _addStop() {
    if (_stops.length >= _maxStops) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('maxStops')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _stops.add(_FieldCtl()));
  }

  void _removeStop(int i) {
    setState(() {
      _stops[i].dispose();
      _stops.removeAt(i);
    });
  }

  /// THE swap («перевернуть маршрут»). Works whenever a destination exists;
  /// a device-location start is materialised as an explicit point so it can
  /// travel to the other side. The stop list reverses along with them.
  void _swap() {
    final st = context.read<AppState>();
    if (_to.place == null && _to.ctrl.text.trim().isEmpty) return;
    var f = _from.place;
    if (f == null && _from.ctrl.text.trim().isEmpty) {
      f = _devicePlace(st);
    }
    if (f == null) return; // no known coordinates at all
    final fText = _from.place == null ? '' : _from.ctrl.text;
    setState(() {
      final fromPlace = _from.place;
      final fromText = fText;
      _from.place = _to.place;
      _from.ctrl.text = _to.ctrl.text;
      _to.place = fromPlace;
      _to.ctrl.text = fromText;
      // Mirror the stops (A → X → Y → B becomes B → Y → X → A).
      final reversed = _stops.reversed.toList();
      _stops.clear();
      _stops.addAll(reversed);
      _from.sug = const [];
      _to.sug = const [];
    });
  }

  LuxPlace? _devicePlace(AppState st) {
    final g = st.lastGps ?? st.lastCamera;
    if (g == null) return null;
    return LuxPlace(
      name: S.of('myLocation'),
      subtitle: '',
      lat: g.lat,
      lon: g.lon,
      kind: 'place',
    );
  }

  /// Resolve whatever is typed into a field: the picked place when it still
  /// matches the text, otherwise a fresh geocode of the text.
  Future<LuxPlace?> _resolve(_FieldCtl f) async {
    if (f.place != null && f.place!.name == f.ctrl.text) return f.place;
    final q = f.ctrl.text.trim();
    if (q.isEmpty) return null;
    try {
      final res = await _geo.suggest(q, near: _anchor(), language: _lang());
      if (res.isEmpty) return null;
      return res.first;
    } catch (_) {
      return null;
    }
  }

  /// v6.7: the planner resolves against MY position, so a French user
  /// typing a French address does not get a same-named street abroad.
  LuxCam? _anchor() => context.read<AppState>().lastGps;

  String _lang() =>
      Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';

  Future<void> _build() async {
    final to = await _resolve(_to);
    if (!mounted) return;
    if (to == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of('noResults')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var from = await _resolve(_from);
    if (from != null && from.lat == to.lat && from.lon == to.lon) {
      from = null; // degenerate A→A — treat as device start
    }
    // Resolve the stops; a stop that cannot be resolved is dropped (the
    // route still builds — a dead field must never block the trip).
    final stops = <LuxPlace>[];
    for (final s in _stops) {
      final p = await _resolve(s);
      if (p != null &&
          (p.lat != to.lat || p.lon != to.lon) &&
          (stops.isEmpty ||
              stops.last.lat != p.lat ||
              stops.last.lon != p.lon)) {
        stops.add(p);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      from == null
          ? RoutePlan.device(to, stops: stops)
          : RoutePlan(from: from, to: to, stops: stops),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    return Column(
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
              child: Icon(Icons.route_rounded, color: t.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.of('planTitle'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: S.of('close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // FROM / stops / TO — real, typeable fields; the swap button sits
        // on the right.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                children: [
                  _EndpointField(
                    ctl: _from,
                    icon: _from.place == null
                        ? Icons.my_location_rounded
                        : Icons.trip_origin_rounded,
                    accent: t.primary,
                    label: S.of('from'),
                    hint: S.of('myLocation'),
                    onChanged: (q) => _onChanged(_from, q),
                    onPick: (p) => _pick(_from, p),
                  ),
                  for (var i = 0; i < _stops.length; i++) ...[
                    const SizedBox(height: 8),
                    _StopField(
                      ctl: _stops[i],
                      index: i,
                      onChanged: (q) => _onChanged(_stops[i], q),
                      onPick: (p) => _pick(_stops[i], p),
                      onRemove: () => _removeStop(i),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _EndpointField(
                    ctl: _to,
                    icon: Icons.place_rounded,
                    accent: const Color(0xFFE2543E),
                    label: S.of('to'),
                    hint: S.of('chooseDest'),
                    onChanged: (q) => _onChanged(_to, q),
                    onPick: (p) => _pick(_to, p),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // THE swap («перевернуть маршрут») button.
            Tooltip(
              message: S.of('swap'),
              child: Material(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _swap,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(
                      Icons.swap_vert_rounded,
                      color: t.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Live suggestions under the fields (each field carries its own).
        for (final f in [_from, ..._stops, _to])
          if (f.sug.isNotEmpty)
            _Suggestions(list: f.sug, onPick: (p) => _pick(f, p)),
        const SizedBox(height: 10),
        // Quick chips: device location / home / work / RECENTS (v5.8).
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            children: [
              _QuickChip(
                icon: Icons.my_location_rounded,
                label: S.of('myLocation'),
                active: _from.place == null && _from.ctrl.text.isEmpty,
                onTap: () {
                  _from.focus.unfocus();
                  setState(() {
                    _from.place = null;
                    _from.ctrl.text = '';
                    _from.sug = const [];
                  });
                },
              ),
              if (state.home != null)
                _QuickChip(
                  icon: Icons.home_rounded,
                  label: S.of('home'),
                  active:
                      _from.place != null &&
                      (_from.place!.lat - state.home!.lat).abs() < 1e-6,
                  onTap: () => _pick(_from, state.home!),
                ),
              if (state.work != null)
                _QuickChip(
                  icon: Icons.work_rounded,
                  label: S.of('work'),
                  active:
                      _from.place != null &&
                      (_from.place!.lat - state.work!.lat).abs() < 1e-6,
                  onTap: () => _pick(_from, state.work!),
                ),
              for (var i = 0; i < state.recents.length && i < 4; i++)
                _QuickChip(
                  icon: Icons.history_rounded,
                  label: state.recents[i].name,
                  active:
                      _to.place != null &&
                      _to.place!.name == state.recents[i].name,
                  onTap: () => _pick(_to, state.recents[i]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // v5.8: add an intermediate stop (A → B → C).
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: t.primary,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          ),
          onPressed: _addStop,
          icon: const Icon(Icons.add_road_rounded, size: 19),
          label: Text(
            S.of('addStop'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        ModeRow(
          mode: state.mode,
          onPick: (m) => context.read<AppState>().setMode(m),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: S.of('buildRoute'),
          icon: Icons.navigation_rounded,
          enabled: _to.place != null || _to.ctrl.text.trim().isNotEmpty,
          onTap: _build,
        ),
      ],
    );
  }
}

/// One endpoint field («Откуда» / «Куда») — a REAL text input: tap it, type,
/// pick a suggestion. No nested search sheet needed.
class _EndpointField extends StatelessWidget {
  const _EndpointField({
    required this.ctl,
    required this.icon,
    required this.accent,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.onPick,
  });

  final _FieldCtl ctl;
  final IconData icon;
  final Color accent;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<LuxPlace> onPick;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final focused = ctl.focus.hasFocus;
    return Material(
      color: t.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ctl.focus.requestFocus(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? accent : t.outline.withValues(alpha: 0.6),
              width: focused ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: t.textMuted,
                      ),
                    ),
                    SizedBox(
                      height: 26,
                      child: TextField(
                        controller: ctl.ctrl,
                        focusNode: ctl.focus,
                        onChanged: onChanged,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: t.onBackground,
                          height: 1.15,
                        ),
                        cursorColor: accent,
                        keyboardType: TextInputType.streetAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: hint,
                          hintStyle: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: t.textMuted,
                          ),
                          suffixIcon: ctl.busy
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  ),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 22,
                            minHeight: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.search_rounded, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// v5.8: one INTERMEDIATE stop field — numbered, deletable.
class _StopField extends StatelessWidget {
  const _StopField({
    required this.ctl,
    required this.index,
    required this.onChanged,
    required this.onPick,
    required this.onRemove,
  });

  final _FieldCtl ctl;
  final int index;
  final ValueChanged<String> onChanged;
  final ValueChanged<LuxPlace> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final focused = ctl.focus.hasFocus;
    final accent = t.secondary;
    return Material(
      color: t.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ctl.focus.requestFocus(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? accent : t.outline.withValues(alpha: 0.6),
              width: focused ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.more_vert_rounded, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${S.of('viaStop')} ${index + 1}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: t.textMuted,
                      ),
                    ),
                    SizedBox(
                      height: 26,
                      child: TextField(
                        controller: ctl.ctrl,
                        focusNode: ctl.focus,
                        onChanged: onChanged,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: t.onBackground,
                          height: 1.15,
                        ),
                        cursorColor: accent,
                        keyboardType: TextInputType.streetAddress,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: S.of('viaStop'),
                          hintStyle: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: S.of('remove'),
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, size: 18, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact live-suggestion list for the focused endpoint field.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.list, required this.onPick});
  final List<LuxPlace> list;
  final ValueChanged<LuxPlace> onPick;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.outline.withValues(alpha: 0.5)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final p = list[i];
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(
              Icons.location_on_outlined,
              size: 19,
              color: t.primary,
            ),
            title: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: t.onBackground),
            ),
            subtitle: p.subtitle.isEmpty
                ? null
                : Text(
                    p.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.textMuted),
                  ),
            onTap: () => onPick(p),
          );
        },
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? t.primary.withValues(alpha: 0.16) : t.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? t.primary : t.outline.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: active ? t.primary : t.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? t.primary : t.onBackground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
