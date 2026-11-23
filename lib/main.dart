import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/network/network_monitor.dart';
import 'core/services/update_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/responsive.dart';
import 'features/addons/presentation/controllers/addons_controller.dart';
import 'features/addons/presentation/screens/addons_screen.dart';
import 'features/addons/presentation/widgets/addons_ui_kit.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';
import 'features/auth/presentation/screens/tmdb_auth_screen.dart';
import 'features/collections/presentation/screens/collections_screen.dart';
import 'features/home/presentation/controllers/home_controller.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/home/presentation/widgets/openflix_splash_screen.dart';
import 'features/home/presentation/widgets/pixel_bottom_nav.dart';
import 'features/my_list/presentation/screens/my_list_screen.dart';
import 'features/player/presentation/controllers/watch_progress_controller.dart';
import 'features/preferences/presentation/controllers/playback_preferences_controller.dart';
import 'features/preferences/presentation/widgets/language_setup_sheet.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/search/presentation/screens/search_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (_) {}
  NetworkMonitor.instance.initialize();

  // Low-RAM tuning: cap the decoded-image cache so a 3GB device never churns,
  // while keeping enough count headroom for long episode lists + poster rows.
  PaintingBinding.instance.imageCache
    ..maximumSize = 250
    ..maximumSizeBytes = 64 << 20; // 64 MiB of decoded images at most

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: OpenFlixApp()));
}

class OpenFlixApp extends StatelessWidget {
  const OpenFlixApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'OpenFlix',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        builder: (context, child) {
          Responsive.init(context);
          return child ?? const SizedBox.shrink();
        },
        home: const _AppAuthGate(),
      );
}

typedef PixelApp = OpenFlixApp;

class _AppAuthGate extends ConsumerWidget {
  const _AppAuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    return switch (authState) {
      AuthInitialCheck() => const Scaffold(
          backgroundColor: Color(0xFF170D20),
          body: SizedBox.expand(),
        ),
      AuthUnauthenticated() => const TmdbAuthScreen(),
      AuthAuthenticated() => const RootShell(),
    };
  }
}

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  bool _showSplash = true;
  bool _deepLinkRouteQueued = false;
  bool _languagePromptShown = false;

  void _maybePromptLanguageSetup() {
    if (_showSplash || _languagePromptShown || !mounted) return;
    final prefsAsync = ref.read(playbackPreferencesControllerProvider);
    final prefs = prefsAsync.valueOrNull;
    if (prefsAsync.hasValue &&
        prefs != null &&
        !prefs.hasCompletedLanguageSetup) {
      _languagePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showLanguageSetupSheet(context, isFirstStartupPrompt: true);
      });
    }
  }

  void _scheduleSilentUpdateCheck() {
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      UpdateService.instance.runSilentStartupCheck(context);
    });
  }

  void _openAddonsForDeepLink() {
    if (_deepLinkRouteQueued || AddonsScreen.isAnyMounted || !mounted) return;
    _deepLinkRouteQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinkRouteQueued = false;
      if (!mounted || AddonsScreen.isAnyMounted) return;
      Navigator.of(context).push<void>(addonsRoute<void>(const AddonsScreen()));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingDeepLinkManifestProvider);
      if (pending != null && pending.trim().isNotEmpty) {
        _openAddonsForDeepLink();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Initialize addons, watch preferences & progress stores early during splash.
    ref.watch(addonsControllerProvider);
    ref.watch(playbackPreferencesControllerProvider);
    ref.watch(watchProgressControllerProvider);
    ref.listen<String?>(pendingDeepLinkManifestProvider, (prev, next) {
      if (next != null && next.trim().isNotEmpty) {
        _openAddonsForDeepLink();
      }
    });
    _maybePromptLanguageSetup();

    final activeTab = ref.watch(activeTabProvider);
    final homeState = ref.watch(homeControllerProvider);
    final loadedShelvesCount = _showSplash
        ? ref.watch(
            shelvesProvider.select(
              (map) => map.values.where((s) => s.status == ShelfStatus.loaded && s.metas.isNotEmpty).length,
            ),
          )
        : 0;
    final isHomeReady =
        (homeState is HomeReady &&
            ((homeState.hero.isNotEmpty && loadedShelvesCount >= 2) ||
                homeState.addonError != null)) ||
        homeState is HomeError;

    return PopScope(
      canPop: activeTab == PixelTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && activeTab != PixelTab.home) {
          ref.read(activeTabProvider.notifier).state = PixelTab.home;
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Scaffold(
            backgroundColor: AppColors.background,
            // IndexedStack keeps Home and Search (and their loaded catalogs/queries) alive across tab switches
            body: IndexedStack(
              index: activeTab.index,
              children: [
                for (final t in PixelTab.values)
                  switch (t) {
                    PixelTab.home => const HomeScreen(),
                    PixelTab.collections => const CollectionsScreen(),
                    PixelTab.myList => const MyListScreen(),
                    PixelTab.search => const SearchScreen(),
                    PixelTab.profile => const ProfileScreen(),
                  },
              ],
            ),
            bottomNavigationBar: PixelBottomNav(
              current: activeTab,
              onChanged: (t) => ref.read(activeTabProvider.notifier).state = t,
            ),
          ),
          if (_showSplash)
            Positioned.fill(
              child: OpenFlixSplashScreen(
                isHomeReady: isHomeReady,
                onFinished: () {
                  if (mounted) {
                    setState(() => _showSplash = false);
                    _maybePromptLanguageSetup();
                    _scheduleSilentUpdateCheck();
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
