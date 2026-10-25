/// Layers sheet (v5.4) — SIMPLIFIED, per the user's contract:
///   • map THEMES moved to Settings (a full picker lives there);
///   • here stay the four LAYER types: Спутник, Рельеф, Просмотр улиц
///     (locked — no free panorama source) and 3D здания.
/// Спутник / Рельеф are basemap toggles: on → that style, off → back to the
/// last vector theme ([AppState.toggleBasemap]).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import 'widgets.dart';

Future<void> showLayersSheet(BuildContext context) => showLuxSheet(
  context: context,
  scrollable: true,
  tag: 'layers',
  builder: (_) => const LayersSheet(),
);

class LayersSheet extends StatelessWidget {
  const LayersSheet({super.key});

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
              child: Icon(Icons.layers_rounded, color: t.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.of('layers'),
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
        const SizedBox(height: 12),

        // Спутник.
        _LayerTile(
          icon: Icons.satellite_alt_rounded,
          title: S.of('satellite'),
          subtitle: S.of('satelliteSub'),
          active: state.mapStyle == MapStyle.satellite,
          onTap: () => state.toggleBasemap(MapStyle.satellite),
        ),
        const SizedBox(height: 8),

        // Рельеф убран по просьбе пользователя (v6.6.1) — спутник остался.

        // Просмотр улиц — honestly locked (no free panorama source).
        _LayerTile(
          icon: Icons.photo_camera_rounded,
          title: S.of('streetView'),
          subtitle: S.of('streetViewLocked'),
          active: false,
          locked: true,
          onTap: () {},
        ),
        const SizedBox(height: 8),

        // Здания — v5.9: the user picks the render mode himself
        // («Добавь здания не 3d а обычные чтобы я сам выбрал!»):
        // Обычные footprints / 3D skyline / Выкл. In every mode except
        // Выкл the houses stay TAPPABLE (выбор здания подсвечивает его).
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: t.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: state.buildingsMode == BuildingsMode.off
                  ? Colors.transparent
                  : t.primary.withValues(alpha: 0.55),
              width: 1.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.view_in_ar_rounded,
                    size: 20,
                    color: state.buildingsMode == BuildingsMode.off
                        ? t.textMuted
                        : t.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    S.of('buildingsMode'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: t.onBackground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<BuildingsMode>(
                  segments: [
                    ButtonSegment(
                      value: BuildingsMode.flat,
                      icon: const Icon(Icons.square_rounded, size: 17),
                      label: Text(
                        S.of('buildingsFlat'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    ButtonSegment(
                      value: BuildingsMode.threeD,
                      icon: const Icon(Icons.view_in_ar_rounded, size: 17),
                      label: Text(
                        S.of('buildings3d'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    ButtonSegment(
                      value: BuildingsMode.off,
                      icon: const Icon(Icons.block_rounded, size: 17),
                      label: Text(
                        S.of('buildingsOff'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                  selected: {state.buildingsMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => state.setBuildingsMode(s.first),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 13, color: t.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      S.of('buildingPickHint'),
                      style: TextStyle(fontSize: 11.5, color: t.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
    this.locked = false,
  });

  final IconData icon;
  final String title, subtitle;
  final bool active;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? t.primary.withValues(alpha: 0.12) : t.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? t.primary : Colors.transparent,
          width: 1.6,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          locked ? Icons.lock_rounded : icon,
          color: locked ? t.textMuted : (active ? t.primary : t.onBackground),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: locked ? t.textMuted : t.onBackground,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: t.textMuted),
        ),
        trailing: active && !locked
            ? Icon(Icons.check_circle_rounded, color: t.primary)
            : null,
        onTap: locked ? null : onTap,
      ),
    );
  }
}
