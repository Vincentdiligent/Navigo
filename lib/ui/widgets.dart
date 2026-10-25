/// Shared UI atoms: glass surfaces, pills and small buttons.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/lux_theme.dart';
import '../core/strings.dart';

/// Palette of the moment for atoms without a provider dependency.
LuxTheme luxThemeOf(BuildContext context) =>
    context.read<AppState>().effectiveTheme;

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.isDark ? t.surface.withValues(alpha: 0.96) : t.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.45 : 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Round 48px floating control (44px+ touch target).
class RoundFab extends StatelessWidget {
  const RoundFab({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.busy = false,
    this.size = 48,
    this.child,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  /// v6.4: true while the underlying operation «ищет» — the button SPINS
  /// (a slim ring replaces the icon) instead of sitting still.
  final bool busy;
  final double size;

  /// Optional icon override (e.g. the rotating compass needle).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: active
            ? t.primary
            : t.isDark
            ? t.surface.withValues(alpha: 0.96)
            : t.surface,
        borderRadius: BorderRadius.circular(size / 2),
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      strokeCap: StrokeCap.round,
                      color: active ? t.onPrimary : t.primary,
                    ),
                  )
                : child ??
                      Icon(
                        icon,
                        size: 22,
                        color: active ? t.onPrimary : t.onBackground,
                      ),
          ),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.progress = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool enabled;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.5,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: t.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: enabled && !progress ? onTap : null,
        child: progress
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Sheet open-bookkeeping (v5.6).
///
/// v5.5 shipped a single boolean guard («ONE sheet at a time») to kill the
/// user's duplicate-window bug. It OVERSHOT: the guard silently swallowed
/// every NESTED open — Настройки → Темы карты / Оффлайн-карты did NOTHING
/// (the settings sheet was already open), the planner's endpoint fields
/// felt dead (their search sheet never came up), and «Построить маршрут…»
/// on a place card was a no-op. The user: «в настройках темы и оффлайн не
/// открываются! … в окне маршрут нельзя ничего сделать».
///
/// v5.6 model: sheets are identified by a TAG. The SAME tag can never be
/// opened twice (the duplicate-window guard lives on), but a DIFFERENT
/// sheet is allowed to stack ON TOP of an open one — exactly like modal
/// routes: Настройки → Темы → pick → back to Настройки.
final Set<String> _openSheetTags = <String>{};

/// True while ANY lux sheet is on screen. The map-tap handler uses this to
/// ignore taps under a modal barrier.
bool get luxSheetOpen => _openSheetTags.isNotEmpty;

/// v5.5 CLASSIC BOTTOM SHEET (the user: «sheets меню — это выезжающие снизу
/// окна, а ты херово сделал»):
///   • full-width, attached to the very bottom edge (no floating margins) —
///     a real Google-Maps-style sheet, rounded TOP corners only;
///   • a drag handle (tap it or drag the sheet down to close);
///   • keyboard-aware WITHOUT touching the map: the Home scaffold now runs
///     with resizeToAvoidBottomInset:false, and the sheet lifts itself via
///     viewInsets padding — the map NEVER moves underneath;
///   • clears the nav bar via viewPadding, so nothing hides behind it.
Future<T?> showLuxSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool scrollable = true,
  String tag = 'sheet',
}) {
  // Duplicate guard: the SAME sheet is already up (double-tap, rebuild) —
  // a second request is a no-op. Different tags stack freely.
  if (_openSheetTags.contains(tag)) return Future<T?>.value();
  _openSheetTags.add(tag);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (ctx) => _SheetFrame(builder: builder, scrollable: scrollable),
  ).whenComplete(() => _openSheetTags.remove(tag));
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.builder, required this.scrollable});

  final WidgetBuilder builder;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    return Padding(
      // The sheet itself rides above the keyboard — the map stays put.
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * (kb > 0 ? 0.72 : 0.9),
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(
            top: BorderSide(color: t.outline.withValues(alpha: 0.9)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 28,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle — tap to close, drag anywhere on the sheet to
            // dismiss (built-in enableDrag).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                child: Container(
                  width: 46,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: t.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Flexible(
              child: Padding(
                // One gutter for every sheet: the frame used to place content
                // flush on the glass, so card rims read as cut-off edges.
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: scrollable
                    ? SingleChildScrollView(child: builder(context))
                    : builder(context),
              ),
            ),
            // Clear the system gesture bar while the keyboard is closed
            // (the keyboard covers it while typing).
            SizedBox(
              height: kb > 0 ? 8 : math.max(mq.viewPadding.bottom, 10.0),
            ),
          ],
        ),
      ),
    );
  }
}

// ── v6.7 SHEET VOCABULARY ────────────────────────────────────────────────
// Settings, offline maps and the theme picker had each grown their own
// header, card and row — four icon sizes, three radii, two switch styles.
// These four atoms are now the only vocabulary the sheets are built from.

/// Sheet header: tinted icon chip, title, one-line subtitle, optional pill
/// and the close button.
class LuxSheetHeader extends StatelessWidget {
  const LuxSheetHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.primary.withValues(alpha: 0.22),
                  t.primary.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: t.primary.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 20, color: t.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      LuxPill(label: badge!),
                    ],
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
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
          IconButton(
            tooltip: S.of('close'),
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, size: 21, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Tiny rounded label (version, size hint, count).
class LuxPill extends StatelessWidget {
  const LuxPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final c = color ?? t.primary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3.5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 9.5 : 11,
              fontWeight: FontWeight.w800,
              color: c,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// One titled group: a card with a small caps header and hairline-separated
/// rows inside.
class LuxGroupCard extends StatelessWidget {
  const LuxGroupCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.headerTrailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    // Only real rows get a separator — chips/segments blocks would gain a
    // floating line with nothing above them.
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Container(
            height: 0.7,
            margin: const EdgeInsets.only(left: 43),
            color: t.outline.withValues(alpha: 0.5),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        // v6.7: the rim used to be a 0.55 hairline on a sheet of the very
        // same colour — «бортики макетов не видны». A full-strength stroke
        // plus a soft lift makes each group read as its own card.
        border: Border.all(
          color: t.outline.withValues(alpha: t.isDark ? 0.9 : 0.75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: t.isDark ? 0.30 : 0.055),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(
              children: [
                Icon(icon, size: 13, color: t.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: t.textMuted,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

/// A single row inside a [LuxGroupCard]: icon chip + title/sub + trailing.
class LuxTile extends StatelessWidget {
  const LuxTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: (selected ? t.primary : t.onBackground).withValues(
                  alpha: selected ? 0.15 : 0.06,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 16,
                color: selected ? t.primary : t.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1.5),
                      child: Text(
                        subtitle!,
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
            if (trailing != null) ...[
              const SizedBox(width: 10),
              DefaultTextStyle(style: const TextStyle(), child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

/// The switch used by every settings row (compact, palette-tinted).
class LuxSwitch extends StatelessWidget {
  const LuxSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Transform.scale(
      scale: 0.86,
      child: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: t.primary,
        activeTrackColor: t.primary.withValues(alpha: 0.32),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// A full-width choice pill.
///
/// Hand-rolled instead of [SegmentedButton]: Material draws a vertical tick
/// between every pair of segments («линии вертикальные» in the user's
/// screenshot), and those ticks cannot be turned off.
class LuxSegment<T> extends StatelessWidget {
  const LuxSegment({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return Container(
      height: (compact ? 34 : 38) + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.onBackground.withValues(alpha: t.isDark ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: t.outline.withValues(alpha: t.isDark ? 0.9 : 0.75),
        ),
      ),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: _LuxSegmentPill<T>(
                segment: s,
                on: selected.contains(s.value),
                radius: 10,
                onTap: () => onChanged({s.value}),
                fontSize: compact ? 11 : 11.5,
                iconSize: compact ? 14 : 15,
              ),
            ),
        ],
      ),
    );
  }
}

class _LuxSegmentPill<T> extends StatelessWidget {
  const _LuxSegmentPill({
    required this.segment,
    required this.on,
    required this.radius,
    required this.onTap,
    required this.fontSize,
    required this.iconSize,
  });

  final ButtonSegment<T> segment;
  final bool on;
  final double radius;
  final VoidCallback onTap;
  final double fontSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: on ? t.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.32),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: on ? t.onPrimary : t.textMuted,
          ),
          child: IconTheme(
            data: IconThemeData(
              size: iconSize,
              color: on ? t.onPrimary : t.textMuted,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (segment.icon != null) ...[
                  segment.icon!,
                  if (segment.label != null) const SizedBox(width: 6),
                ],
                if (segment.label != null) segment.label!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
