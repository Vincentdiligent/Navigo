/// v6.7 place search: a real full-screen window with live suggestions.
///
/// Two bugs the user named: «выходит снизу отдельное окно sheets — зачем?»
/// and «полностью окно полноценное, а не поверх экрана». So this is not a
/// modal sheet any more — it is its own opaque page on the navigator stack,
/// and because the map lives in the route BELOW, this page is free to resize
/// with the keyboard (the old «панель поднимает карту» ban only applied to
/// sheets drawn over the live map).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../places/geocoding.dart';
import 'widgets.dart';

Future<LuxPlace?> openPlaceSearch(BuildContext context, {LuxCam? camera}) =>
    Navigator.of(context).push<LuxPlace>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlaceSearchPage(camera: camera),
      ),
    );

class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({super.key, this.camera});

  /// Live camera — the anchor when there is no GPS fix yet.
  final LuxCam? camera;

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  // Autofocus on a page that is still animating in is unreliable on some
  // devices (the IME never shows) — an explicit FocusNode + a post-frame
  // requestFocus is deterministic.
  final FocusNode _focus = FocusNode();
  final Geocoding _geo = Geocoding();
  Timer? _timer;
  int _token = 0;
  List<LuxPlace> _remote = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// My position decides the ranking — a fix first, the visible map second.
  LuxCam? _anchor(AppState state) => state.lastGps ?? widget.camera;

  void _onChanged(String q) {
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 300),
      () => _searchRemote(q.trim()),
    );
  }

  Future<void> _searchRemote(String q) async {
    final token = ++_token;
    if (q.length < 2) {
      setState(() {
        _remote = [];
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _geo.suggest(
        q,
        near: _anchor(context.read<AppState>()),
        language: Localizations.maybeLocaleOf(context)?.toLanguageTag(),
      );
      if (!mounted || token != _token) return;
      setState(() {
        _remote = res;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _remote = [];
        _busy = false;
      });
    }
  }

  /// Saved places answer instantly, before the network does — that is half
  /// of why Google's list feels immediate.
  List<LuxPlace> _local(AppState state, String q) {
    if (q.length < 2) return [];
    final needle = q.toLowerCase();
    bool hit(LuxPlace p) =>
        p.name.toLowerCase().contains(needle) ||
        p.subtitle.toLowerCase().contains(needle);
    final mine = <LuxPlace?>[
      state.home,
      state.work,
      ...state.favorites,
    ].whereType<LuxPlace>().where(hit).toList();
    final seen = state.recents.where(hit).toList();
    return <LuxPlace>[...mine, ...seen];
  }

  void _pick(LuxPlace p) {
    _focus.unfocus();
    Navigator.of(context).pop(p);
  }

  void _clear() {
    _ctrl.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    final q = _ctrl.text.trim();
    final searching = q.length >= 2;
    final local = _local(state, q);
    final remote = _remote
        .where((p) => !local.any((l) => l.lat == p.lat && l.lon == p.lon))
        .toList();
    final nothing = searching && !_busy && local.isEmpty && remote.isEmpty;

    return Scaffold(
      backgroundColor: t.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: t.onBackground,
                    ),
                  ),
                  Expanded(
                    child: _SearchField(
                      controller: _ctrl,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      onSubmitted: (v) => _searchRemote(v.trim()),
                      onClear: _clear,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: nothing
                  ? _EmptyState(query: q)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                      children: [
                        if (!searching)
                          ..._quickSection(state)
                        else ...[
                          if (local.isNotEmpty) ...[
                            for (final p in local.take(4)) _row(p, saved: true),
                          ],
                          if (remote.isNotEmpty || _busy) ...[
                            if (local.isNotEmpty) const _SectionGap(),
                            if (_busy && remote.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                ),
                              )
                            else
                              for (final p in remote) _row(p),
                          ],
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _quickSection(AppState state) {
    final t = luxThemeOf(context);
    final mine = <LuxPlace?>[
      state.home,
      state.work,
      ...state.favorites,
    ].whereType<LuxPlace>().toList();
    if (mine.isEmpty && state.recents.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 34),
          child: Center(
            child: Text(
              S.of('emptyFavorites'),
              style: TextStyle(color: t.textMuted, fontSize: 13.5),
            ),
          ),
        ),
      ];
    }
    return [
      for (final p in mine) _row(p, saved: true),
      if (state.recents.isNotEmpty) ...[
        const _SectionGap(),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: t.textMuted),
              const SizedBox(width: 7),
              Text(
                S.of('recent').toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
        ),
        for (final p in state.recents.take(8)) _row(p),
      ],
    ];
  }

  Widget _row(LuxPlace p, {bool saved = false}) {
    final icon = p.kind == 'home'
        ? Icons.home_rounded
        : p.kind == 'work'
        ? Icons.work_rounded
        : saved
        ? Icons.star_rounded
        : Icons.place_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: LuxTile(
        icon: icon,
        title: p.name,
        subtitle: p.subtitle.isEmpty ? null : p.subtitle,
        selected: saved,
        trailing: p.distanceKm == null
            ? null
            : LuxPill(label: _distance(p.distanceKm!), dense: true),
        onTap: () => _pick(p),
      ),
    );
  }

  String _distance(double km) {
    // Same shape as AppState's own distance formatter (dot decimal + the
    // localized unit key).
    final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return '$text ${S.of('km')}';
  }
}

/// The field itself — a filled pill, the search glyph and a clear button.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: t.outline.withValues(alpha: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search_rounded, size: 21, color: t.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              // Explicit colors: the inherited style can render
              // light-on-light depending on the active palette.
              style: TextStyle(color: t.onBackground, fontSize: 15.5),
              cursorColor: t.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: S.of('searchHint'),
                hintStyle: TextStyle(color: t.textMuted, fontSize: 14.5),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: onClear,
              icon: Icon(Icons.cancel_rounded, size: 21, color: t.textMuted),
            ),
        ],
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Container(height: 0.7, color: t.outline.withValues(alpha: 0.5)),
    );
  }
}

/// Nothing matched — say it next to the words the user actually typed, so
/// an empty list is never ambiguous.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_rounded, size: 40, color: t.textMuted),
            const SizedBox(height: 12),
            Text(
              S.of('noResults'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '«$query»',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
