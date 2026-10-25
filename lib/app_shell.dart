import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/lux_theme.dart';
import 'ui/home_screen.dart';

/// Root: Material skins from the active palette + edge-to-edge status icons.
class NavigoApp extends StatelessWidget {
  const NavigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final theme = state.effectiveTheme;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                theme.isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                theme.isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: MaterialApp(
            title: 'Navigo',
            debugShowCheckedModeBanner: false,
            theme: _skin(theme),
            // v5.4: the map is created ONLY after prefs are loaded, so the
            // restored camera is known before the first frame — the app
            // opens where the user closed it, never in Paris first.
            home: state.loaded
                ? const HomeScreen()
                : const _BootSplash(),
          ),
        );
      },
    );
  }

  ThemeData _skin(LuxTheme t) {
    final scheme = ColorScheme(
      brightness: t.isDark ? Brightness.dark : Brightness.light,
      primary: t.primary,
      onPrimary: t.onPrimary,
      secondary: t.secondary,
      onSecondary: t.isDark ? const Color(0xFF241A02) : Colors.white,
      error: const Color(0xFFFF7B7B),
      onError: const Color(0xFF2A0707),
      surface: t.surface,
      onSurface: t.onBackground,
      surfaceContainerHighest: t.surfaceAlt,
      onSurfaceVariant: t.textMuted,
      outline: t.outline,
      outlineVariant: t.outline,
      surfaceContainer: t.surface,
      surfaceContainerLow: t.surface,
      surfaceContainerLowest: t.background,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.background,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: 'Roboto',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// v5.4: a minimal splash shown while SharedPreferences load (a few
/// milliseconds). Prevents the «always Paris» flash on every start.
class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101317),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.near_me_rounded, size: 44, color: Color(0xFF4FD8C4)),
            SizedBox(height: 14),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
