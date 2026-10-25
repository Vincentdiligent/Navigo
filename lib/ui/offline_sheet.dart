/// Offline maps manager (v5.4, redesigned in v6.7) — the «отдельный пункт
/// оффлайн карты для стран и их регионов» the user asked for.
///
/// Uses MapLibre Native's OfflineManager through maplibre_gl:
///  • downloadOfflineRegion — fetches every style resource (vector tiles,
///    glyphs, sprites) inside a bbox/zoom range for the CLASSIC style URL.
///    The cache is shared, so the downloaded tiles automatically serve ALL
///    Liberty-based themes (Classic, Forest, the premium recolors).
///  • getListOfRegions / deleteOfflineRegion — the installed-packs list.
///
/// v6.7 («оффлайн карты тоже надо само окно лучше сделать красивее»): the
/// sheet is now built from the shared atoms in widgets.dart and the 56-country
/// catalog is an accordion instead of one endless flat list.
library;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../core/strings.dart';
import '../map/style_pack.dart';
import '../offline/regions.dart';
import 'widgets.dart';

Future<void> showOfflineSheet(BuildContext context) => showLuxSheet(
  context: context,
  scrollable: false,
  tag: 'offline',
  builder: (_) => const OfflineSheet(),
);

enum _Level { overview, standard, detailed }

extension _LevelX on _Level {
  double get maxZoom => switch (this) {
    _Level.overview => 9,
    _Level.standard => 11,
    _Level.detailed => 13,
  };
  String get label => switch (this) {
    _Level.overview => S.of('levelOverview'),
    _Level.standard => S.of('levelStandard'),
    _Level.detailed => S.of('levelDetailed'),
  };
}

/// Localized country name, with a guard.
///
/// `S.of` answers with the RAW KEY when a translation is missing, and the
/// catalog key is `c<Key>` — so an untranslated country rendered as
/// «cAzerbaijan» / «cSouth Korea» (the bug the user reported). Falling back
/// to the bare key gives a readable English name instead.
String countryDisplayName(OfflineCountry c) {
  final k = 'c${c.key}';
  final n = S.of(k);
  return n == k ? c.key : n;
}

class OfflineSheet extends StatefulWidget {
  const OfflineSheet({super.key});

  @override
  State<OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<OfflineSheet> {
  _Level _level = _Level.standard;
  String _query = '';
  List<ml.OfflineRegion> _installed = [];
  bool _loadingInstalled = true;

  /// Country keys the user opened. A search opens every match implicitly.
  final Set<String> _open = {};

  /// Region identity → live download progress.
  final Map<String, double> _active = {};
  final Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    try {
      final regions = await ml.getListOfRegions();
      if (!mounted) return;
      setState(() {
        _installed = regions;
        _loadingInstalled = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInstalled = false);
    }
  }

  String _keyOf(OfflineCountry c, OfflineRegionInfo r) => '${c.key}/${r.name}';

  String _installedNameOf(ml.OfflineRegion reg) {
    final m = reg.metadata;
    final n = (m['name'] ?? '') as String;
    if (n.isNotEmpty) return n;
    final b = reg.definition.bounds;
    return '${b.southwest.latitude.toStringAsFixed(1)}, ${b.southwest.longitude.toStringAsFixed(1)} → ${b.northeast.latitude.toStringAsFixed(1)}, ${b.northeast.longitude.toStringAsFixed(1)}';
  }

  /// «0–11» → the same words the picker uses, so the installed list reads
  /// like the catalog and not like a zoom constant.
  String _installedLevelOf(ml.OfflineRegion reg) {
    final z = reg.definition.maxZoom.round();
    for (final l in _Level.values) {
      if (l.maxZoom.round() == z) return l.label;
    }
    return '0–$z';
  }

  Future<void> _download(OfflineCountry c, OfflineRegionInfo r) async {
    final key = _keyOf(c, r);
    if (_active[key] != null) return;
    setState(() => _active[key] = 0.0);
    try {
      await ml.downloadOfflineRegion(
        ml.OfflineRegionDefinition(
          bounds: ml.LatLngBounds(
            southwest: ml.LatLng(r.south, r.west),
            northeast: ml.LatLng(r.north, r.east),
          ),
          // The vector tiles of the CLASSIC style serve every Liberty-based
          // theme — one download, 12 themes covered.
          mapStyleUrl: kStyleLiberty,
          minZoom: 0,
          maxZoom: _level.maxZoom,
        ),
        metadata: {'name': r.name, 'country': c.key},
        onEvent: (status) {
          if (!mounted) return;
          switch (status) {
            case ml.InProgress(:final progress):
              if (progress >= 0) {
                setState(() => _active[key] = progress.clamp(0.0, 1.0));
              }
            case ml.Success():
              setState(() {
                _active.remove(key);
                _done.add(key);
              });
              _refreshInstalled();
            case ml.Error():
              setState(() => _active.remove(key));
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${S.of('downloadFailed')}: ${r.name}'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _active.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${S.of('downloadFailed')}: ${r.name}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteRegion(ml.OfflineRegion reg) async {
    try {
      await ml.deleteOfflineRegion(reg.id);
      await ml.clearAmbientCache();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of('regionDeleted')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _refreshInstalled();
  }

  bool _matches(OfflineCountry c, String q) =>
      q.isEmpty ||
      countryDisplayName(c).toLowerCase().contains(q) ||
      c.key.toLowerCase().contains(q) ||
      c.regions.any((r) => r.name.toLowerCase().contains(q));

  /// Searching opens every hit and clearing it closes everything again, so
  /// the accordion never leaks the search state back into the plain list.
  void _setQuery(String v) {
    final q = v.trim().toLowerCase();
    setState(() {
      _query = v;
      _open.clear();
      if (q.isNotEmpty) {
        for (final c in kOfflineCountries) {
          if (_matches(c, q)) _open.add(c.key);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final query = _query.trim().toLowerCase();
    final countries =
        kOfflineCountries
            .map(
              (c) => OfflineCountry(
                c.key,
                c.regions
                    .where(
                      (r) =>
                          query.isEmpty ||
                          countryDisplayName(c).toLowerCase().contains(query) ||
                          c.key.toLowerCase().contains(query) ||
                          r.name.toLowerCase().contains(query),
                    )
                    .toList(),
              ),
            )
            .where((c) => c.regions.isNotEmpty)
            .toList()
          ..sort(
            (a, b) => countryDisplayName(
              a,
            ).toLowerCase().compareTo(countryDisplayName(b).toLowerCase()),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxSheetHeader(
          icon: Icons.download_rounded,
          title: S.of('offlineTitle'),
          subtitle: S.of('offlineRowSub'),
          badge: _installed.isEmpty ? null : '${_installed.length}',
        ),
        _SearchBox(query: _query, onChanged: _setQuery),
        const SizedBox(height: 10),

        // Detail level + the two notes, so the sheet has no loose caption rows.
        LuxGroupCard(
          icon: Icons.layers_rounded,
          title: S.of('offlineLevel'),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LuxSegment<_Level>(
                    segments: [
                      for (final l in _Level.values)
                        ButtonSegment(value: l, label: Text(l.label)),
                    ],
                    selected: {_level},
                    onChanged: (s) => setState(() => _level = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.of('offlineHint'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: t.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      S.of('offlineNote'),
                      style: TextStyle(
                        fontSize: 10,
                        color: t.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Installed areas — the card only exists once there is something
        // to manage («Пока ничего не скачано» is not worth a whole block).
        if (_loadingInstalled || _installed.isNotEmpty)
          LuxGroupCard(
            icon: Icons.offline_pin_rounded,
            title: S.of('offlineInstalled'),
            children: _loadingInstalled
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ]
                : [
                    for (final reg in _installed)
                      _InstalledRow(
                        name: _installedNameOf(reg),
                        level: _installedLevelOf(reg),
                        onDelete: () => _deleteRegion(reg),
                      ),
                  ],
          ),

        // Catalog.
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  S.of('offlineCatalog').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: t.textMuted,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              Text(
                '${countries.length}',
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ],
          ),
        ),
        Flexible(
          child: countries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Text(
                      S.of('noResults'),
                      style: TextStyle(fontSize: 12.5, color: t.textMuted),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 4),
                  shrinkWrap: true,
                  itemCount: countries.length,
                  itemBuilder: (context, i) {
                    final c = countries[i];
                    return _CountryCard(
                      country: c,
                      name: countryDisplayName(c),
                      expanded: _open.contains(c.key),
                      onToggle: () => setState(() {
                        if (!_open.remove(c.key)) _open.add(c.key);
                      }),
                      keyOf: _keyOf,
                      active: _active,
                      done: _done,
                      onDownload: (r) => _download(c, r),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceAlt,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: t.outline.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(Icons.search_rounded, size: 19, color: t.textMuted),
          ),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: TextStyle(color: t.onBackground, fontSize: 13.5),
              cursorColor: t.primary,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: S.of('searchRegion'),
                hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (query.isNotEmpty)
            IconButton(
              tooltip: S.of('clear'),
              onPressed: () => onChanged(''),
              icon: Icon(Icons.cancel_rounded, size: 18, color: t.textMuted),
              visualDensity: VisualDensity.compact,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _InstalledRow extends StatelessWidget {
  const _InstalledRow({
    required this.name,
    required this.level,
    required this.onDelete,
  });

  final String name;
  final String level;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return LuxTile(
      icon: Icons.offline_pin_rounded,
      title: name,
      subtitle: level,
      selected: true,
      trailing: IconButton(
        tooltip: S.of('deleteRegion'),
        icon: Icon(Icons.delete_outline_rounded, size: 19, color: t.textMuted),
        visualDensity: VisualDensity.compact,
        onPressed: onDelete,
      ),
      onTap: onDelete,
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({
    required this.country,
    required this.name,
    required this.expanded,
    required this.onToggle,
    required this.keyOf,
    required this.active,
    required this.done,
    required this.onDownload,
  });

  final OfflineCountry country;
  final String name;
  final bool expanded;
  final VoidCallback onToggle;
  final String Function(OfflineCountry, OfflineRegionInfo) keyOf;
  final Map<String, double> active;
  final Set<String> done;
  final ValueChanged<OfflineRegionInfo> onDownload;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: expanded
              ? t.primary.withValues(alpha: 0.45)
              : t.outline.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 9, 9),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: t.primary.withValues(
                        alpha: expanded ? 0.17 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.public_rounded,
                      size: 15,
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  LuxPill(label: '${country.regions.length}', dense: true),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in country.regions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: _RegionRow(
                        region: r,
                        progress: active[keyOf(country, r)],
                        isDone: done.contains(keyOf(country, r)),
                        onDownload: () => onDownload(r),
                      ),
                    ),
                ],
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

class _RegionRow extends StatelessWidget {
  const _RegionRow({
    required this.region,
    required this.progress,
    required this.isDone,
    required this.onDownload,
  });

  final OfflineRegionInfo region;
  final double? progress; // null → idle
  final bool isDone;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final busy = progress != null;
    final pct = busy ? (progress! * 100).round() : 0;
    final km = region.sizeKm;
    // Coarse: a diagonal size is an order-of-magnitude hint, not a measure.
    final size =
        '${km >= 1000 ? (km / 100).round() * 100 : km.round()} ${S.of('km')}';
    final status = busy
        ? '${S.of('downloading')} $pct%'
        : isDone
        ? S.of('downloadDone')
        : '≈ $size';

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
      decoration: BoxDecoration(
        color: isDone ? Colors.green.withValues(alpha: 0.07) : t.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDone
              ? Colors.green.withValues(alpha: 0.28)
              : t.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: busy
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          value: progress! <= 0 ? null : progress,
                          strokeWidth: 2.2,
                          color: t.primary,
                          backgroundColor: t.outline.withValues(alpha: 0.4),
                        ),
                      ),
                      Text(
                        '$pct',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          color: t.primary,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    isDone
                        ? Icons.check_circle_rounded
                        : Icons.download_rounded,
                    size: 19,
                    color: isDone ? Colors.green.shade600 : t.textMuted,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDone
                          ? Colors.green.shade700
                          : busy
                          ? t.primary
                          : t.textMuted,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _DownloadButton(
            busy: busy,
            isDone: isDone,
            onPressed: busy ? null : onDownload,
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.busy,
    required this.isDone,
    required this.onPressed,
  });

  final bool busy;
  final bool isDone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final accent = isDone ? Colors.green.shade600 : t.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: busy
                ? 0.06
                : isDone
                ? 0.10
                : 0.15,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isDone ? '⟳' : S.of('download'),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: busy ? t.textMuted : accent,
          ),
        ),
      ),
    );
  }
}
