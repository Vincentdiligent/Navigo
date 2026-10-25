/// v6.8 «Офлайн-голос» — the window where a voice is chosen and downloaded.
///
/// Built on the same sheet vocabulary as Настройки / Оффлайн карты / Темы
/// (LuxSheetHeader + LuxGroupCard + LuxTile), because the user's complaint was
/// never about sheets in settings — it was about the search field popping a
/// mini-sheet over the live map.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/strings.dart';
import '../route/voice.dart';
import '../voice/piper_tts.dart';
import '../voice/voice_packs.dart';
import 'widgets.dart';

Future<void> openVoiceSettings(BuildContext context) => showLuxSheet(
  context: context,
  scrollable: true,
  tag: 'voice',
  builder: (_) => const VoiceSheet(),
);

class VoiceSheet extends StatefulWidget {
  const VoiceSheet();

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final VoicePackStore _store = VoicePackStore.I;

  /// Parallel to [VoicePacks.all].
  List<bool> _installed = List<bool>.filled(VoicePacks.all.length, false);
  int _used = 0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_scan);
    _scan();
  }

  @override
  void dispose() {
    _store.removeListener(_scan);
    super.dispose();
  }

  /// Re-reads the file system (a few stat calls) and repaints.
  Future<void> _scan() async {
    final flags = await VoicePackStore.I.installedAll();
    final used = await VoicePackStore.I.usedBytes();
    if (!mounted) return;
    setState(() {
      _installed = flags;
      _used = used;
    });
  }

  Future<void> _download(VoicePack p) async {
    await _store.install(p);
    if (!mounted) return;
    // The live speaker picks the new voice up immediately — no restart, and
    // the first announcement after a download is not lost.
    await NavVoice.I?.pickVoice();
    context.read<AppState>().touchVoice();
    await _scan();
  }

  Future<void> _remove(VoicePack p) async {
    await _store.remove(p);
    await PiperTts.I.forget();
    if (!mounted) return;
    await NavVoice.I?.pickVoice();
    context.read<AppState>().touchVoice();
    await _scan();
  }

  String _speakLine(AppState state) {
    final v = NavVoice.I;
    if (v == null) return '';
    return switch (v.engineLabel) {
      'offline' => '${S.of('voiceSpeakOffline')} · ${v.offlinePack?.label ?? ''}',
      'system' => S.of('voiceSpeakSystem'),
      _ => state.voiceEngine == 'offline'
          ? S.of('voiceSpeakNone')
          : S.of('noVoice'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = luxThemeOf(context);
    final lang = state.locale.languageCode.toLowerCase();
    final line = _speakLine(state);

    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuxSheetHeader(
            icon: Icons.record_voice_over_rounded,
            title: S.of('voiceOffline'),
            subtitle: S.of('voiceOfflineSub'),
          ),

          // ── Which speaker ───────────────────────────────────────────────
          LuxGroupCard(
            icon: Icons.spatial_audio_off_rounded,
            title: S.of('voiceEngineBy'),
            children: [
              _Field(
                icon: Icons.swap_horiz_rounded,
                label: S.of('voiceEngineBy'),
                hint: S.of('voiceEngineAutoSub'),
                child: LuxSegment<String>(
                  compact: true,
                  segments: [
                    ButtonSegment(
                      value: 'auto',
                      label: Text(S.of('engineAuto')),
                    ),
                    ButtonSegment(
                      value: 'system',
                      label: Text(S.of('engineSystem')),
                    ),
                    ButtonSegment(
                      value: 'offline',
                      label: Text(S.of('engineOffline')),
                    ),
                  ],
                  selected: {state.voiceEngine},
                  onChanged: (s) async {
                    await context.read<AppState>().setVoiceEngine(s.first);
                    if (!mounted) return;
                    await NavVoice.I?.pickVoice();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              if (line.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NavVoice.I?.usingOffline ?? false
                              ? Colors.green.shade500
                              : (NavVoice.I?.available ?? false)
                          ? t.primary
                          : Colors.redAccent.shade200,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          line,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              LuxTile(
                icon: Icons.volume_up_rounded,
                title: S.of('voiceTest'),
                trailing: const Icon(
                  Icons.play_circle_outline_rounded,
                  size: 20,
                ),
                onTap: () async {
                  final v = NavVoice.I;
                  if (v == null || !await v.engineReady()) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(S.of('noVoiceEngine')),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    return;
                  }
                  await v.test();
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── The voices themselves ───────────────────────────────────────
          LuxGroupCard(
            icon: Icons.download_rounded,
            title: S.of('voicePacks'),
            children: [
              for (var i = 0; i < VoicePacks.all.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: _PackRow(
                    pack: VoicePacks.all[i],
                    installed: _installed[i],
                    recommended: VoicePacks.all[i].lang == lang,
                    inUse: NavVoice.I?.offlinePack?.id == VoicePacks.all[i].id,
                    progress: _store.progressOf(VoicePacks.all[i].id),
                    busy: _store.isBusy(VoicePacks.all[i].id),
                    error: _store.errorOf(VoicePacks.all[i].id),
                    onDownload: () => _download(VoicePacks.all[i]),
                    onRemove: () => _remove(VoicePacks.all[i]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                child: Text(
                  '${S.of('voicePacksHint')}  '
                  '${S.of('voiceUsed')}: ${_human(_used)}',
                  style: TextStyle(fontSize: 11.5, color: t.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.child,
    this.hint,
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
            padding: const EdgeInsets.only(top: 9),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// One language: what it is, how big, and the one button it needs.
class _PackRow extends StatelessWidget {
  const _PackRow({
    required this.pack,
    required this.installed,
    required this.recommended,
    required this.inUse,
    required this.busy,
    required this.onDownload,
    required this.onRemove,
    this.progress,
    this.error = '',
  });

  final VoicePack pack;
  final bool installed;
  final bool recommended;
  final bool inUse;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onRemove;
  final double? progress;
  final String error;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    final accent = installed ? Colors.green.shade600 : t.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: t.surfaceAlt.withValues(alpha: t.isDark ? 0.5 : 0.45),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: inUse
              ? accent.withValues(alpha: 0.8)
              : t.outline.withValues(alpha: t.isDark ? 0.85 : 0.7),
          width: inUse ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pack.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (inUse) ...[
                          const SizedBox(width: 7),
                          LuxPill(label: S.of('voiceInUse'), dense: true),
                        ] else if (recommended) ...[
                          const SizedBox(width: 7),
                          LuxPill(
                            label: S.of('voiceRecommend'),
                            dense: true,
                            color: t.textMuted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      installed
                          ? '${S.of('voiceInstalled')} · '
                              '${S.of('voiceFreeNote')} ${pack.license}'
                          : '${_human(pack.totalBytes)} · '
                              '${S.of('voiceFreeNote')} ${pack.license}',
                      style: TextStyle(fontSize: 11.5, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (installed)
                IconButton(
                  tooltip: S.of('voiceRemove'),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: t.textMuted,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : onRemove,
                )
              else
                _ActionChip(
                  label: busy
                      ? '${(100 * (progress ?? 0)).round()}%'
                      : '${S.of('voiceDownload')} · ${_human(pack.totalBytes)}',
                  accent: accent,
                  busy: busy,
                  onTap: onDownload,
                ),
            ],
          ),
          if (busy && progress != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: t.onBackground.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                '${S.of('voiceFailed')}: $error',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.redAccent.shade200,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = luxThemeOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: busy ? null : onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: busy ? 0.06 : 0.15),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!busy) ...[
              Icon(Icons.download_rounded, size: 14, color: accent),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: busy ? t.textMuted : accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bytes in the user's own unit («63 МБ», «63 MB», «63 Mo»).
String _human(int bytes) {
  const unit = {
    'ru': 'МБ',
    'fr': 'Mo',
    'en': 'MB',
    'es': 'MB',
    'de': 'MB',
  };
  const kilo = {
    'ru': 'КБ',
    'fr': 'Ko',
    'en': 'KB',
    'es': 'KB',
    'de': 'KB',
  };
  final lang = S.current.languageCode;
  final mb = bytes / 1048576.0;
  if (mb >= 1) {
    return '${mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1)} '
        '${unit[lang] ?? 'MB'}';
  }
  return '${(bytes / 1024.0).toStringAsFixed(0)} ${kilo[lang] ?? 'KB'}';
}
