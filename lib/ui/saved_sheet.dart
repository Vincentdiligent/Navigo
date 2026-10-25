/// Saved places window (v5.3) — the «окно избранное» the user asked for.
/// Lists Home, Work and every favorite with three actions per row:
/// tap → show on the map, ➤ → build a route, 🗑 → REMOVE the point
/// («поставленную избранную точку как убрать?»).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import 'widgets.dart';

/// What the caller should do with the returned place.
enum SavedAction { show, route }

class SavedPick {
  const SavedPick(this.place, this.action);
  final LuxPlace place;
  final SavedAction action;
}

Future<SavedPick?> showSavedSheet(BuildContext context) => showLuxSheet(
      context: context,
      tag: 'saved',
      builder: (_) => const SavedSheet(),
    );

class SavedSheet extends StatelessWidget {
  const SavedSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    final entries = <_SavedEntry>[
      if (state.home != null) _SavedEntry(state.home!, SavedKind.home),
      if (state.work != null) _SavedEntry(state.work!, SavedKind.work),
      for (final f in state.favorites) _SavedEntry(f, SavedKind.favorite),
    ];

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
              child: Icon(Icons.star_rounded, color: t.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.of('favorites'),
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
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Icon(Icons.star_border_rounded, size: 44, color: t.outline),
                const SizedBox(height: 10),
                Text(
                  S.of('emptyFavorites'),
                  style: TextStyle(color: t.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  S.of('emptyFavoritesHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return _SavedRow(
                  entry: e,
                  onShow: () => Navigator.of(context)
                      .pop(SavedPick(e.place, SavedAction.show)),
                  onRoute: () => Navigator.of(context)
                      .pop(SavedPick(e.place, SavedAction.route)),
                  onDelete: () async {
                    final removed = await context.read<AppState>().removeSaved(e.place);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          removed ? S.of('removed') : S.of('nothingRemoved'),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

enum SavedKind { home, work, favorite }

class _SavedEntry {
  const _SavedEntry(this.place, this.kind);
  final LuxPlace place;
  final SavedKind kind;
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.entry,
    required this.onShow,
    required this.onRoute,
    required this.onDelete,
  });

  final _SavedEntry entry;
  final VoidCallback onShow;
  final VoidCallback onRoute;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final (icon, accent) = switch (entry.kind) {
      SavedKind.home => (Icons.home_rounded, const Color(0xFF2E9E62)),
      SavedKind.work => (Icons.work_rounded, const Color(0xFFE2543E)),
      // v5.8: the favorite keeps its chosen pin color.
      SavedKind.favorite => (
          Icons.star_rounded,
          kFavPinColors[entry.place.colorIdx.clamp(0, kFavPinColors.length - 1)],
        ),
    };
    final subtitle = entry.place.subtitle.isEmpty
        ? '${entry.place.lat.toStringAsFixed(5)}, ${entry.place.lon.toStringAsFixed(5)}'
        : entry.place.subtitle;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: accent),
      ),
      title: Text(
        entry.place.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.onBackground, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: t.textMuted, fontSize: 12.5),
      ),
      onTap: onShow,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: S.of('routeTo'),
            icon: const Icon(Icons.navigation_rounded, size: 20),
            color: t.primary,
            onPressed: onRoute,
          ),
          IconButton(
            tooltip: S.of('remove'),
            icon: const Icon(Icons.delete_outline_rounded, size: 21),
            color: t.textMuted,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
