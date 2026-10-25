/// Settings (v6.7) — ONE bottom sheet, rebuilt on the shared sheet
/// vocabulary (LuxSheetHeader / LuxGroupCard / LuxTile / LuxSwitch).
///
/// v5.3 lesson: the full-screen page buried everything and the user saw
/// «только темы на всё окно настроек». v6.7 lesson: three sheets had grown
/// three different visual languages — one card style now, sections read as
/// iOS-style inset groups, and the About block shows the REAL version.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/lux_theme.dart';
import '../core/strings.dart';
import '../map/map_catalog.dart';
import '../map/poi_chips.dart';
import '../map/style_pack.dart';
import '../route/voice.dart';
import 'offline_sheet.dart';
import 'voice_sheet.dart';
import 'widgets.dart';

Future<void> openSettings(BuildContext context) => showLuxSheet(
  context: context,
  scrollable: true,
  tag: 'settings',
  builder: (_) => const SettingsSheet(),
);

/// The full-height map-theme picker, opened from Settings → Карта.
Future<void> openThemePicker(BuildContext context) => showLuxSheet(
  context: context,
  scrollable: true,
  tag: 'themePicker',
  builder: (_) => const _ThemePickerSheet(),
);

class SettingsSheet extends StatelessWidget {
  const SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.effectiveTheme;
    final themeInfo = kMapStyleCatalog.firstWhere(
      (i) => i.style == state.mapStyle,
      orElse: () => kMapStyleCatalog.first,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxSheetHeader(icon: Icons.tune_rounded, title: S.of('settings')),

        // ── Карта ────────────────────────────────────────────────────────
        LuxGroupCard(
          icon: Icons.map_rounded,
          title: S.of('secMap'),
          children: [
            LuxTile(
              icon: Icons.style_rounded,
              title: S.of('mapThemes'),
              subtitle:
                  '${themeInfo.title()} · '
                  '${S.of(state.premiumRender ? 'renderFamilyAtlas' : 'renderFamilyClassic')}',
              selected: true,
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => openThemePicker(context),
            ),
            // v5.9: the buildings mode (Обычные / 3D / Выкл) — the user picks
            // it himself, so it stays a first-class control, not a sub-sheet.
            _Block(
              icon: Icons.view_in_ar_rounded,
              label: S.of('buildingsMode'),
              child: LuxSegment<BuildingsMode>(
                compact: true,
                segments: [
                  ButtonSegment(
                    value: BuildingsMode.flat,
                    label: Text(S.of('buildingsFlat')),
                  ),
                  ButtonSegment(
                    value: BuildingsMode.threeD,
                    label: const Text('3D'),
                  ),
                  ButtonSegment(
                    value: BuildingsMode.off,
                    label: Text(S.of('buildingsOff')),
                  ),
                ],
                selected: {state.buildingsMode},
                onChanged: (s) =>
                    context.read<AppState>().setBuildingsMode(s.first),
              ),
            ),
            LuxTile(
              icon: Icons.dark_mode_rounded,
              title: S.of('autoNightOn'),
              subtitle: S.of('autoNightSub'),
              trailing: LuxSwitch(
                value: state.autoNightOn,
                onChanged: (v) => context.read<AppState>().setAutoNight(v),
              ),
            ),
            // v6.8: «какая будет ночная карта на выбор» — the shade theme is
            // his own choice, picked from the dark catalog only. His day
            // theme is never part of this decision.
            if (state.autoNightOn)
              _Block(
                icon: Icons.nightlight_rounded,
                label: S.of('nightTheme'),
                hint: S.of('nightThemeSub'),
                child: _NightChoiceRow(
                  selected: state.nightStyle,
                  onChanged: (s) => context.read<AppState>().setNightStyle(s),
                ),
              ),
            LuxTile(
              icon: Icons.travel_explore_rounded,
              title: S.of('onlineInfo'),
              subtitle: S.of('onlineInfoSub'),
              trailing: LuxSwitch(
                value: state.onlineInfoOn,
                onChanged: (v) => context.read<AppState>().setOnlineInfo(v),
              ),
            ),
          ],
        ),

        // ── Навигация ────────────────────────────────────────────────────
        LuxGroupCard(
          icon: Icons.navigation_rounded,
          title: S.of('secNavigation'),
          children: [
            LuxTile(
              icon: Icons.record_voice_over_rounded,
              title: S.of('voiceOn'),
              trailing: LuxSwitch(
                value: state.voiceOn,
                onChanged: (v) {
                  context.read<AppState>().setVoice(v);
                  // v6.2: keep the live TTS gate in sync from settings too.
                  NavVoice.I?.enabled = v;
                },
              ),
            ),
            // v6.7: «Проверить голос» first told the truth about the engine;
            // v6.8 it moved inside the voice window, which now also carries
            // the speaker choice and the offline voice downloads.
            LuxTile(
              icon: Icons.graphic_eq_rounded,
              title: S.of('voiceOffline'),
              subtitle: _voiceSummary(state),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                size: 20,
              ),
              onTap: () => openVoiceSettings(context),
            ),
            LuxTile(
              icon: Icons.vibration_rounded,
              title: S.of('hapticsOn'),
              subtitle: S.of('hapticsSub'),
              trailing: LuxSwitch(
                value: state.hapticsOn,
                onChanged: (v) => context.read<AppState>().setHaptics(v),
              ),
            ),
            LuxTile(
              icon: Icons.photo_camera_rounded,
              title: S.of('camWarnOn'),
              subtitle: S.of('camWarnSub'),
              trailing: LuxSwitch(
                value: state.camWarnOn,
                onChanged: (v) => context.read<AppState>().setCamWarn(v),
              ),
            ),
            _Block(
              icon: Icons.radio_button_checked_rounded,
              label: S.of('puckStyle'),
              hint: S.of('puckStyleSub'),
              child: _IconChoiceRow<PuckPref>(
                values: const [
                  (PuckPref.auto, Icons.auto_mode_rounded, 'puckAuto'),
                  (PuckPref.arrow, Icons.navigation_rounded, 'puckArrow'),
                  (PuckPref.car, Icons.directions_car_rounded, 'puckCar'),
                  (PuckPref.dot, Icons.radio_button_checked_rounded, 'puckDot'),
                ],
                selected: state.puckPref,
                onChanged: (v) => context.read<AppState>().setPuckPref(v),
              ),
            ),
            _Block(
              icon: _modeIcon(state.mode),
              label: S.of('travelMode'),
              hint: S.of(_modeKey(state.mode)),
              child: LuxSegment<TravelMode>(
                compact: true,
                segments: [
                  ButtonSegment(
                    value: TravelMode.car,
                    icon: const Icon(Icons.directions_car_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: TravelMode.bike,
                    icon: const Icon(Icons.directions_bike_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: TravelMode.foot,
                    icon: const Icon(Icons.directions_walk_rounded, size: 17),
                  ),
                  ButtonSegment(
                    value: TravelMode.transit,
                    icon: const Icon(
                      Icons.directions_transit_rounded,
                      size: 17,
                    ),
                  ),
                ],
                selected: {state.mode},
                onChanged: (s) => context.read<AppState>().setMode(s.first),
              ),
            ),
            _Block(
              icon: Icons.straighten_rounded,
              label: S.of('units'),
              child: LuxSegment<bool>(
                compact: true,
                segments: [
                  ButtonSegment(value: true, label: Text(S.of('metric'))),
                  ButtonSegment(value: false, label: Text(S.of('imperial'))),
                ],
                selected: {state.metric},
                onChanged: (s) => context.read<AppState>().setMetric(s.first),
              ),
            ),
            // v5.5: route options («быстрее/короче, платные…»).
            _Block(
              icon: Icons.alt_route_rounded,
              label: S.of('routeOptions'),
              hint: S.of('routeOptionsSub'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LuxSegment<RoutePref>(
                    compact: true,
                    segments: [
                      ButtonSegment(
                        value: RoutePref.fast,
                        icon: const Icon(Icons.bolt_rounded, size: 14),
                        label: Text(S.of('prefFast')),
                      ),
                      ButtonSegment(
                        value: RoutePref.short,
                        icon: const Icon(Icons.straighten_rounded, size: 14),
                        label: Text(S.of('prefShort')),
                      ),
                    ],
                    selected: {state.routePref},
                    onChanged: (s) =>
                        context.read<AppState>().setRoutePref(s.first),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Filter(
                        label: S.of('noTolls'),
                        selected: state.avoidTolls,
                        onChanged: (v) =>
                            context.read<AppState>().setAvoidTolls(v),
                      ),
                      _Filter(
                        label: S.of('noMotorways'),
                        selected: state.avoidMotorways,
                        onChanged: (v) =>
                            context.read<AppState>().setAvoidMotorways(v),
                      ),
                      _Filter(
                        label: S.of('noFerries'),
                        selected: state.avoidFerries,
                        onChanged: (v) =>
                            context.read<AppState>().setAvoidFerries(v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            LuxTile(
              icon: Icons.history_rounded,
              title: S.of('clearRecents'),
              trailing: const Icon(Icons.delete_sweep_rounded, size: 19),
              onTap: () => _clearRecents(context),
            ),
          ],
        ),

        // ── Оформление ───────────────────────────────────────────────────
        LuxGroupCard(
          icon: Icons.contrast_rounded,
          title: S.of('secLook'),
          children: [
            const _AppLookRow(),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                S.of('appLookSub'),
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ),
          ],
        ),

        // ── Данные и язык ────────────────────────────────────────────────
        LuxGroupCard(
          icon: Icons.download_rounded,
          title: S.of('secOffline'),
          children: [
            LuxTile(
              icon: Icons.offline_pin_rounded,
              title: S.of('offlineMaps'),
              subtitle: S.of('offlineRowSub'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => showOfflineSheet(context),
            ),
            _Block(
              icon: Icons.language_rounded,
              label: S.of('language'),
              child: const _LanguageChips(),
            ),
          ],
        ),

        // ── О приложении ─────────────────────────────────────────────────
        LuxGroupCard(
          icon: Icons.info_rounded,
          title: S.of('secAbout'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [t.primary, t.secondary],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.navigation_rounded,
                      color: t.onPrimary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.of('appName'),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            S.of('aboutSub'),
                            style: TextStyle(
                              fontSize: 11,
                              color: t.textMuted,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  LuxPill(label: kAppVersion, icon: Icons.verified_rounded),
                ],
              ),
            ),
            LuxTile(icon: Icons.map_rounded, title: S.of('mapData')),
            LuxTile(
              icon: Icons.satellite_alt_rounded,
              title: S.of('satelliteCredit'),
            ),
            LuxTile(icon: Icons.route_rounded, title: S.of('routingBy')),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  static IconData _modeIcon(TravelMode m) => switch (m) {
    TravelMode.car => Icons.directions_car_rounded,
    TravelMode.bike => Icons.directions_bike_rounded,
    TravelMode.foot => Icons.directions_walk_rounded,
    TravelMode.transit => Icons.directions_transit_rounded,
  };

  static String _modeKey(TravelMode m) => switch (m) {
    TravelMode.car => 'car',
    TravelMode.bike => 'bike',
    TravelMode.foot => 'foot',
    TravelMode.transit => 'transit',
  };

  /// v6.8: who is actually reading the prompts — the settings row tells the
  /// truth before the user even opens the voice window.
  String _voiceSummary(AppState state) {
    final v = NavVoice.I;
    if (v == null) return S.of('voiceOfflineSub');
    return switch (v.engineLabel) {
      'offline' =>
        '${S.of('voiceSpeakOffline')} · ${v.offlinePack?.label ?? ''}',
      'system' => S.of('voiceSpeakSystem'),
      _ => S.of('voiceSpeakNone'),
    };
  }

  Future<void> _clearRecents(BuildContext context) async {
    await context.read<AppState>().clearRecents();
    if (!context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(S.of('recentsCleared')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// A labelled control block inside a [LuxGroupCard] (segmented buttons,
/// chip rows) — same left rail as the icon of a [LuxTile].
class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.label,
    this.hint,
    required this.child,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: t.onBackground.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: t.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1.5),
                        child: Text(
                          hint!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.textMuted,
                            height: 1.25,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 43, top: 8),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ],
      ),
    );
  }
}

/// v6.8: the AUTO-NIGHT theme picker — one pill per dark catalog theme,
/// each carrying a swatch painted from that theme's OWN palette, so the
/// choice is a picture, not a name to remember.
class _NightChoiceRow extends StatelessWidget {
  const _NightChoiceRow({
    required this.selected,
    required this.onChanged,
  });

  final MapStyle selected;
  final ValueChanged<MapStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final options = kMapStyleCatalog
        .where((i) => isNightCapable(i.style))
        .toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final i in options)
          GestureDetector(
            onTap: () => onChanged(i.style),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: i.style == selected
                    ? t.primary.withValues(alpha: 0.14)
                    : t.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: i.style == selected
                      ? t.primary
                      : t.outline.withValues(alpha: 0.5),
                  width: i.style == selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StyleSwatch(info: i),
                  const SizedBox(width: 7),
                  Text(
                    i.title(),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: i.style == selected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: i.style == selected ? t.primary : t.onBackground,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A 20×20 miniature of a theme: land, one road, a water corner, a building.
class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.info});

  final MapStyleInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: info.land,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: info.accent, width: 1.2),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -2,
            right: -2,
            top: 8,
            height: 3,
            child: ColoredBox(color: info.major),
          ),
          Positioned(left: 0, bottom: 0, width: 8, height: 8, child: ColoredBox(color: info.water)),
          Positioned(
            right: 1,
            top: 1,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: info.building,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + label choice row (the puck picker) — one compact pill per option.
class _IconChoiceRow<T> extends StatelessWidget {
  const _IconChoiceRow({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, IconData, String)> values;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (value, icon, key) in values)
          GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: value == selected
                    ? t.primary.withValues(alpha: 0.14)
                    : t.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: value == selected
                      ? t.primary
                      : t.outline.withValues(alpha: 0.5),
                  width: value == selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: value == selected ? t.primary : t.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    S.of(key),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: value == selected
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: value == selected ? t.primary : t.onBackground,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A route-preference toggle chip.
class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: t.primary.withValues(alpha: 0.14),
      side: BorderSide(
        color: selected ? t.primary : t.outline.withValues(alpha: 0.5),
        width: selected ? 1.4 : 1,
      ),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: selected ? t.primary : t.onBackground,
      ),
      onSelected: onChanged,
    );
  }
}

/// Light / dark app look — two big selectable cards.
class _AppLookRow extends StatelessWidget {
  const _AppLookRow();

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    Widget look(LuxTheme theme, String label, IconData icon) {
      final active = state.theme.id == theme.id;
      return Expanded(
        child: GestureDetector(
          onTap: () => state.setTheme(theme),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: active ? t.primary.withValues(alpha: 0.12) : t.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? t.primary : t.outline.withValues(alpha: 0.5),
                width: active ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: active ? t.primary : t.textMuted),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? t.primary : t.onBackground,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        look(kLuxThemes.first, S.of('appLight'), Icons.light_mode_rounded),
        const SizedBox(width: 10),
        look(kLuxThemes.last, S.of('appDark'), Icons.dark_mode_rounded),
      ],
    );
  }
}

class _LanguageChips extends StatelessWidget {
  const _LanguageChips();

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    // v6.2: five languages, English first (also the default).
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (code, key) in const [
          (kEn, 'langEn'),
          (kEs, 'langEs'),
          (kDe, 'langDe'),
          (kFr, 'langFr'),
          (kRu, 'langRu'),
        ])
          GestureDetector(
            onTap: () => state.setLocale(code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: state.locale.languageCode == code.languageCode
                    ? t.primary
                    : t.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                S.of(key),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: state.locale.languageCode == code.languageCode
                      ? t.onPrimary
                      : t.onBackground,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact grid of ALL map themes (moved OUT of the layers sheet —
/// themes live in Settings only, per the v5.4 contract).
///
/// v6.7: tighter cards (bigger thumbnails, no duplicated badges), the family
/// switch slimmed to one line, and the group headers turned into pills.
class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final state = context.watch<AppState>();
    final atlas = state.premiumRender;
    // v6.8.3: «Атлас» and «Оникс» ARE the premium documents (the user: «в
    // классических темах убери оникс, он премиум!») — they are offered by the
    // Atlas family only. They stay in [kMapStyleCatalog] because the AUTO-NIGHT
    // pill row picks its night theme from there.
    bool inFamily(MapStyleInfo i) =>
        atlas || (i.style != MapStyle.silk && i.style != MapStyle.onyx);
    final groups = [
      (
        S.of('sectionBase'),
        kMapStyleCatalog.where((i) => i.group == 0 && inFamily(i)).toList(),
      ),
      (
        S.of('sectionLight'),
        kMapStyleCatalog.where((i) => i.group == 1 && inFamily(i)).toList(),
      ),
      (
        S.of('sectionDark'),
        kMapStyleCatalog.where((i) => i.group == 2 && inFamily(i)).toList(),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxSheetHeader(
          icon: Icons.palette_rounded,
          title: S.of('mapThemes'),
          subtitle: S.of(
            atlas ? 'renderFamilyAtlasSub' : 'renderFamilyClassicSub',
          ),
        ),
        _RenderFamilySwitch(
          atlas: atlas,
          onChanged: (v) async {
            final s = state.mapStyle;
            if (!v && (s == MapStyle.silk || s == MapStyle.onyx)) {
              // Leaving the family must not strand the map on a theme the
              // grid no longer offers: light Atlas → Graphite, dark Onyx →
              // Noir, i.e. the same mood in the classic engine.
              await state.setMapStyle(
                s == MapStyle.silk ? MapStyle.graphite : MapStyle.noir,
                premium: false,
              );
            } else {
              await state.setPremiumRender(v);
            }
          },
        ),
        const SizedBox(height: 12),
        for (final (title, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: t.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: t.textMuted,
                    letterSpacing: 0.9,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 0.7,
                    margin: const EdgeInsets.only(left: 10),
                    color: t.outline.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.18,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) =>
                _ThemeCardSmall(info: items[i], atlas: atlas),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Классика ↔ Премиум Atlas, one slim line.
class _RenderFamilySwitch extends StatelessWidget {
  const _RenderFamilySwitch({required this.atlas, required this.onChanged});

  final bool atlas;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    Widget seg(bool active, IconData icon, String label) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!atlas),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: active ? t.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: active ? Colors.white : t.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : t.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: t.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          seg(!atlas, Icons.map_rounded, S.of('renderFamilyClassic')),
          seg(atlas, Icons.auto_awesome_rounded, S.of('renderFamilyAtlas')),
        ],
      ),
    );
  }
}

/// Compact theme card: the basemap preview IS the card — the name rides on a
/// gradient strip, the selection is a ring plus a small check.
class _ThemeCardSmall extends StatelessWidget {
  const _ThemeCardSmall({required this.info, this.atlas = false});

  final MapStyleInfo info;
  final bool atlas;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = state.mapStyle == info.style;
    return GestureDetector(
      onTap: () async {
        await state.setMapStyle(info.style, premium: atlas);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? info.accent
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: info.accent.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _MiniBasemap(info: info, atlas: atlas),
              ),
              // Name strip — always readable, whatever the basemap colors.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(7, 10, 7, 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: info.dark ? 0.62 : 0.45),
                      ],
                    ),
                  ),
                  child: Text(
                    info.title(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: info.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.6),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini basemap painter (land/park/water/roads/route) from the catalog.
class _MiniBasemap extends CustomPainter {
  _MiniBasemap({required this.info, this.atlas = false});
  final MapStyleInfo info;

  /// v6.6.1: in the Atlas family the preview must show the NEW rendering —
  /// POI chips and a route in the theme's own signal color, cased so it
  /// reads as "the route" instead of "another road".
  final bool atlas;

  @override
  void paint(Canvas canvas, Size size) {
    Paint p(Color c) => Paint()..color = c;
    canvas.drawRect(Offset.zero & size, p(info.land));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.42, size.width * 0.46, size.height),
        const Radius.circular(6),
      ),
      p(info.park),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.55, 0, size.width * 0.45, size.height),
      p(info.water),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.52,
          size.height * 0.55,
          size.width * 0.3,
          size.height * 0.3,
        ),
        const Radius.circular(3),
      ),
      p(info.building),
    );
    void stroke(Offset a, Offset b, Color c, double w) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = c
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }

    stroke(
      Offset(size.width * 0.1, size.height * 0.12),
      Offset(size.width * 0.72, size.height * 0.9),
      info.minor,
      2.6,
    );
    stroke(
      Offset(size.width * 0.34, 0),
      Offset(size.width * 0.52, size.height),
      info.casing,
      7,
    );
    stroke(
      Offset(size.width * 0.34, 0),
      Offset(size.width * 0.52, size.height),
      info.major,
      4.6,
    );
    // Imagery has no palette of its own — its card keeps the plain preview
    // even in the Atlas family.
    final pal = atlas ? atlasRenderPaletteOf(info.style) : null;
    final deco = pal == null ? null : atlasDecoOf(pal);
    final route = Path()
      ..moveTo(size.width * 0.05, size.height * 0.9)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.55,
        size.width * 0.82,
        size.height * 0.32,
      );
    if (deco != null) {
      canvas.drawPath(
        route,
        Paint()
          ..color = _decoColor(deco.routeCasing)
          ..strokeWidth = 6.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawPath(
      route,
      Paint()
        ..color = deco == null ? info.accent : _decoColor(deco.route)
        ..strokeWidth = 3.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (deco != null) {
      // The chip system is what makes Atlas read as Atlas: three category
      // chips in this palette's own body / ring / glyph colors.
      final glyphs = poiChipSwatches(dark: deco.dark, deco: deco);
      final spots = [
        Offset(size.width * 0.24, size.height * 0.28),
        Offset(size.width * 0.66, size.height * 0.62),
        Offset(size.width * 0.40, size.height * 0.74),
      ];
      const r = 5.4;
      for (var i = 0; i < spots.length; i++) {
        canvas.drawCircle(spots[i], r + 0.9, p(const Color(0x33000000)));
        canvas.drawCircle(spots[i], r, p(_decoColor(deco.chipBody)));
        canvas.drawCircle(
          spots[i],
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = _decoColor(deco.chipRing),
        );
        canvas.drawCircle(spots[i], r * 0.44, p(glyphs[i]));
      }
    }
  }

  static Color _decoColor(Clr c) =>
      Color.fromARGB(((c.a * 255).round()).clamp(0, 255), c.r, c.g, c.b);

  @override
  bool shouldRepaint(_MiniBasemap old) =>
      old.info != info || old.atlas != atlas;
}
