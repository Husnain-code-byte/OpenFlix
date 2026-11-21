import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/features/addons/presentation/screens/addons_screen.dart';
import 'package:pixel/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pixel/features/details/data/tmdb_models.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/details/presentation/widgets/detail_widgets.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/widgets/pixel_bottom_nav.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';
import 'package:pixel/features/profile/presentation/screens/liked_screen.dart';
import 'package:pixel/features/profile/presentation/screens/profile_screen.dart';

class _FakeProfileDio implements Dio {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 404,
      );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'success': true} as T,
      );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);

  final AuthState _initial;
  int syncCalls = 0;
  int logoutCalls = 0;
  bool syncResult = true;

  @override
  AuthState build() => _initial;

  @override
  Future<bool> syncNow() async {
    syncCalls++;
    return syncResult;
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AuthUnauthenticated();
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<TmdbRepository> createRepo() async {
    final repo = TmdbRepository(_FakeProfileDio());
    await repo.setMyList(
      imdbId: 'tt1234567',
      mediaType: 'movie',
      inMyList: true,
      meta: const MetaModel(id: 'tt1234567', type: 'movie', name: 'Movie 1'),
    );
    await repo.setMyList(
      imdbId: 'tt7654321',
      mediaType: 'movie',
      inMyList: true,
      meta: const MetaModel(id: 'tt7654321', type: 'movie', name: 'Movie 2'),
    );
    await repo.setUserRating(
      imdbId: 'tt1234567',
      mediaType: 'movie',
      rating: 9.0,
      meta: const MetaModel(id: 'tt1234567', type: 'movie', name: 'Movie 1'),
    );
    return repo;
  }

  testWidgets('ProfileScreen matches updated Figma layout and counts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = await createRepo();
    final fakeAuth = _FakeAuthController(
      const AuthAuthenticated(
        sessionId: 'sess_1',
        profile: TmdbAccountProfile(id: 42, username: 'joynance'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(() => fakeAuth),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('joynance'), findsOneWidget);
    expect(find.text('TMDB'), findsNothing);
    expect(find.text('@joynance · ID #42'), findsNothing);

    expect(find.text('2'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Liked'), findsOneWidget);

    expect(find.text('Sync with TMDB'), findsOneWidget);
    expect(find.text('Disconnect TMDB Account'), findsOneWidget);
    expect(find.text('Addons'), findsOneWidget);

    expect(
      tester.getRect(find.text('Addons')).top,
      greaterThan(tester.getRect(find.text('Disconnect TMDB Account')).bottom),
    );

    await tester.tap(find.text('Sync with TMDB'));
    await tester.pump();
    expect(fakeAuth.syncCalls, 1);

    await tester.tap(find.text('Addons'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AddonsScreen), findsOneWidget);
    expect(find.text('Add Addon'), findsWidgets);

    Navigator.of(tester.element(find.byType(AddonsScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Disconnect TMDB Account'));
    await tester.pump();
    expect(fakeAuth.logoutCalls, 1);
  });

  testWidgets('ProfileScreen handles long usernames and responsive viewports without overflow', (tester) async {
    final repo = await createRepo();
    final fakeAuth = _FakeAuthController(
      const AuthAuthenticated(
        sessionId: 'sess_2',
        profile: TmdbAccountProfile(
          id: 99,
          username: 'very_long_username_that_must_truncate_cleanly_across_screens',
        ),
      ),
    );

    for (final size in const [Size(390, 915), Size(768, 1024), Size(1440, 900)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(repo),
            authControllerProvider.overrideWith(() => fakeAuth),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: ProfileScreen()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('ProfileScreen disables sync button and shows syncing label while syncing', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = await createRepo();
    final fakeAuth = _FakeAuthController(
      const AuthAuthenticated(
        sessionId: 'sess_3',
        profile: TmdbAccountProfile(id: 42, username: 'joynance'),
        isSyncing: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(() => fakeAuth),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Syncing with TMDB...'), findsOneWidget);
    await tester.tap(find.text('Syncing with TMDB...'));
    await tester.pump();
    expect(fakeAuth.syncCalls, 0);
  });

  testWidgets('Tapping My List card switches to My List tab and tapping Liked opens 3-row LikedScreen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = await createRepo();
    await repo.setUserRating(
      imdbId: 'tt0903747',
      mediaType: 'series',
      rating: 9.0,
      meta: const MetaModel(id: 'tt0903747', type: 'series', name: 'Breaking Bad'),
    );
    await repo.setUserRating(
      imdbId: 'tt0388629',
      mediaType: 'series',
      rating: 9.0,
      isAnime: true,
      meta: const MetaModel(id: 'tt0388629', type: 'series', name: 'One Piece'),
    );

    final fakeAuth = _FakeAuthController(
      const AuthAuthenticated(
        sessionId: 'sess_4',
        profile: TmdbAccountProfile(id: 42, username: 'joynance'),
      ),
    );

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(() => fakeAuth),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: ProfileScreen()),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(container.read(activeTabProvider), PixelTab.home);

    // Tap My List stat card -> switches activeTabProvider to PixelTab.myList
    await tester.tap(find.text('My List'));
    await tester.pump();
    expect(container.read(activeTabProvider), PixelTab.myList);

    // Tap Liked stat card -> opens LikedScreen with Movies, TV Shows, and Anime rows
    await tester.tap(find.text('Liked'));
    await tester.pumpAndSettle();

    expect(find.byType(LikedScreen), findsOneWidget);
    expect(find.byType(PixelBottomNav), findsOneWidget);
    expect(find.text('Liked'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.byType(PosterRow), findsNWidgets(3));
    expect(find.byKey(const ValueKey<String>('liked_movies_row')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('liked_tv_shows_row')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('liked_anime_row')), findsOneWidget);

    // Back button pops back to ProfileScreen
    await tester.tap(find.byType(DetailBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LikedScreen), findsNothing);
    expect(find.text('Profile'), findsOneWidget);

    // Re-open LikedScreen and tap bottom nav Search tab -> switches tab & pops
    await tester.tap(find.text('Liked'));
    await tester.pumpAndSettle();
    expect(find.byType(LikedScreen), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(PixelBottomNav),
      matching: find.text('Search'),
    ));
    await tester.pumpAndSettle();
    expect(container.read(activeTabProvider), PixelTab.search);
    expect(find.byType(LikedScreen), findsNothing);
  });

  testWidgets('LikedScreen shows empty row copy when user has no likes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = TmdbRepository(_FakeProfileDio());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const LikedScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Liked'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('Movies you like will appear here.'), findsOneWidget);
    expect(find.text('TV shows you like will appear here.'), findsOneWidget);
    expect(find.text('Anime you like will appear here.'), findsOneWidget);
  });
}
