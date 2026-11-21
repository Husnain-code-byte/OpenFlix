import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../anime/data/anime_id_map.dart';
import '../../../details/data/tmdb_models.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../../personalization/presentation/controllers/personalized_rows_controller.dart';

enum AuthOnboardingStep {
  welcome,
  signIn,
}

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitialCheck extends AuthState {
  const AuthInitialCheck();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({
    this.step = AuthOnboardingStep.welcome,
    this.requestToken,
    this.approvalUrl,
    this.isPreparingToken = false,
    this.isPollingApproval = false,
    this.isCompletingSync = false,
    this.errorMessage,
  });

  final AuthOnboardingStep step;
  final String? requestToken;
  final String? approvalUrl;
  final bool isPreparingToken;
  final bool isPollingApproval;
  final bool isCompletingSync;
  final String? errorMessage;

  AuthUnauthenticated copyWith({
    AuthOnboardingStep? step,
    String? requestToken,
    String? approvalUrl,
    bool? isPreparingToken,
    bool? isPollingApproval,
    bool? isCompletingSync,
    String? errorMessage,
    bool clearError = false,
  }) =>
      AuthUnauthenticated(
        step: step ?? this.step,
        requestToken: requestToken ?? this.requestToken,
        approvalUrl: approvalUrl ?? this.approvalUrl,
        isPreparingToken: isPreparingToken ?? this.isPreparingToken,
        isPollingApproval: isPollingApproval ?? this.isPollingApproval,
        isCompletingSync: isCompletingSync ?? this.isCompletingSync,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [
        step,
        requestToken,
        approvalUrl,
        isPreparingToken,
        isPollingApproval,
        isCompletingSync,
        errorMessage,
      ];
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.sessionId,
    required this.profile,
    this.isSyncing = false,
    this.syncError,
  });

  final String sessionId;
  final TmdbAccountProfile profile;
  final bool isSyncing;
  final String? syncError;

  AuthAuthenticated copyWith({
    String? sessionId,
    TmdbAccountProfile? profile,
    bool? isSyncing,
    String? syncError,
    bool clearSyncError = false,
  }) =>
      AuthAuthenticated(
        sessionId: sessionId ?? this.sessionId,
        profile: profile ?? this.profile,
        isSyncing: isSyncing ?? this.isSyncing,
        syncError: clearSyncError ? null : (syncError ?? this.syncError),
      );

  @override
  List<Object?> get props => [sessionId, profile, isSyncing, syncError];
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResumed);

  final void Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

class AuthController extends Notifier<AuthState> {
  static const MethodChannel _launcherChannel = MethodChannel('openflix/launcher');
  static const Duration _pollInterval = Duration(seconds: 3);

  late TmdbRepository _tmdbRepo;
  Timer? _pollTimer;
  CancelToken? _cancelToken;
  bool _pollInFlight = false;
  String? _activeRequestToken;
  DateTime? _tokenCreatedAt;

  /// Set once TMDB has issued a `session_id` for an approved token. A request token is
  /// single-use, so from this point we must retry the profile/sync step with this
  /// session instead of polling the (now consumed) token again.
  String? _pendingSessionId;
  late final _ResumeObserver _resumeObserver;
  bool _disposed = false;

  @override
  AuthState build() {
    _disposed = false;
    _tmdbRepo = ref.watch(tmdbRepositoryProvider);
    _resumeObserver = _ResumeObserver(_onAppResumed);
    WidgetsBinding.instance.addObserver(_resumeObserver);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(_resumeObserver);
      _disposeTimers();
    });
    Future.microtask(_checkExistingSession);
    return const AuthInitialCheck();
  }

  void _disposeTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _pollInFlight = false;
  }

  /// When the user returns from the browser (or any other app), check for approval
  /// immediately and make sure the polling timer is alive — Android may have frozen
  /// it while the app was in the background.
  void _onAppResumed() {
    final cur = state;
    if (cur is AuthAuthenticated) {
      final lastAt = _tmdbRepo.lastSuccessfulSyncAt;
      final stale = lastAt == null ||
          DateTime.now().difference(lastAt) > const Duration(minutes: 2);
      if (!cur.isSyncing &&
          (_tmdbRepo.hasPendingSyncOps || !_tmdbRepo.lastSyncSucceeded || stale)) {
        _syncAndRefreshPersonalized();
      }
      return;
    }
    if (cur is! AuthUnauthenticated || cur.step != AuthOnboardingStep.signIn) return;
    final token = _activeRequestToken;
    if (token == null && _pendingSessionId == null) return;
    if (_pollTimer == null || !_pollTimer!.isActive) {
      _startPolling(token ?? '');
    }
    unawaited(_pollOnce(token ?? ''));
  }

  void _syncAndRefreshPersonalized() {
    unawaited(
      _syncAccount(pushLocal: _tmdbRepo.hasPendingSyncOps).then((_) {
        if (!_disposed) {
          ref.read(personalizedRowsControllerProvider.notifier).loadAll();
        }
      }),
    );
  }

  /// Pulls the TMDB Watchlist + Ratings (anime included, classified from TMDB data and
  /// the bundled anime ID map). [pushLocal] first uploads device-only entries to TMDB.
  Future<void> _syncAccount({
    bool pushLocal = false,
    CancelToken? cancelToken,
    bool throwOnError = false,
  }) async {
    final animeIdMap = ref.read(animeIdMapProvider);
    await animeIdMap.ensureLoaded();
    await _tmdbRepo.syncTmdbAccountData(
      cancelToken: cancelToken,
      animeIdMap: animeIdMap,
      pushLocalOnly: pushLocal,
      throwOnError: throwOnError,
    );
  }

  Future<void> _checkExistingSession() async {
    await _tmdbRepo.ensureInteractionsLoaded();
    if (_tmdbRepo.isAuthenticated &&
        _tmdbRepo.userSessionId != null &&
        _tmdbRepo.accountProfile != null) {
      await _tmdbRepo.clearPendingAuth();
      state = AuthAuthenticated(
        sessionId: _tmdbRepo.userSessionId!,
        profile: _tmdbRepo.accountProfile!,
      );
      _syncAndRefreshPersonalized();
      return;
    }

    // The app may have been killed while the user was approving in the browser:
    // resume that exact login rather than generating a new token (which would orphan
    // the approval the user just gave).
    final pending = await _tmdbRepo.loadPendingAuth();
    if (pending != null) {
      _cancelToken = CancelToken();
      _activeRequestToken = pending.requestToken;
      _tokenCreatedAt = pending.createdAt;
      _pendingSessionId = pending.sessionId;
      state = AuthUnauthenticated(
        step: AuthOnboardingStep.signIn,
        requestToken: pending.requestToken,
        approvalUrl: TmdbRepository.buildApprovalUrl(pending.requestToken),
        isPollingApproval: true,
      );
      _startPolling(pending.requestToken);
      unawaited(_pollOnce(pending.requestToken));
      return;
    }
    state = const AuthUnauthenticated(step: AuthOnboardingStep.welcome);
  }

  /// Moves from Screen 1 (`Netflix · Welcome`) to Screen 2 (`Netflix · Sign in`),
  /// immediately generating a fresh TMDB `request_token` and starting the
  /// 3-second approval polling loop.
  Future<void> proceedToSignIn() async {
    _resetPendingState();
    _cancelToken = CancelToken();
    state = const AuthUnauthenticated(
      step: AuthOnboardingStep.signIn,
      isPreparingToken: true,
    );
    await _generateTokenAndStartPolling();
  }

  /// Navigates back from Screen 2 (`Sign in`) to Screen 1 (`Welcome`).
  void backToWelcome() {
    _resetPendingState();
    state = const AuthUnauthenticated(step: AuthOnboardingStep.welcome);
  }

  void _resetPendingState() {
    _disposeTimers();
    _activeRequestToken = null;
    _tokenCreatedAt = null;
    _pendingSessionId = null;
    unawaited(_tmdbRepo.clearPendingAuth());
  }

  /// Regenerates the TMDB `request_token` and restarts auto-polling.
  Future<void> retryTokenGeneration() async {
    // An approved session must never be discarded by a manual retry — just finish it.
    final issued = _pendingSessionId;
    if (issued != null) {
      if (_pollTimer == null || !_pollTimer!.isActive) {
        _startPolling(_activeRequestToken ?? '');
      }
      unawaited(_pollOnce(_activeRequestToken ?? ''));
      return;
    }
    _resetPendingState();
    _cancelToken = CancelToken();
    final cur = state;
    if (cur is AuthUnauthenticated) {
      state = cur.copyWith(
        step: AuthOnboardingStep.signIn,
        isPreparingToken: true,
        clearError: true,
      );
    } else {
      state = const AuthUnauthenticated(
        step: AuthOnboardingStep.signIn,
        isPreparingToken: true,
      );
    }
    await _generateTokenAndStartPolling();
  }

  Future<void> _generateTokenAndStartPolling() async {
    try {
      final token = await _tmdbRepo.createRequestToken(cancelToken: _cancelToken);
      final url = TmdbRepository.buildApprovalUrl(token);
      _activeRequestToken = token;
      _tokenCreatedAt = DateTime.now();
      // Persist immediately so approval survives the app being killed in the background.
      unawaited(_tmdbRepo.savePendingAuth(
        requestToken: token,
        createdAt: _tokenCreatedAt!,
      ));
      state = AuthUnauthenticated(
        step: AuthOnboardingStep.signIn,
        requestToken: token,
        approvalUrl: url,
        isPreparingToken: false,
        isPollingApproval: true,
      );
      _startPolling(token);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      state = const AuthUnauthenticated(
        step: AuthOnboardingStep.signIn,
        isPreparingToken: false,
        errorMessage: 'Unable to reach TMDB. Check your connection and try again.',
      );
    } catch (_) {
      state = const AuthUnauthenticated(
        step: AuthOnboardingStep.signIn,
        isPreparingToken: false,
        errorMessage: 'Could not generate a TMDB authentication link. Please retry.',
      );
    }
  }

  void _startPolling(String requestToken) {
    _pollTimer?.cancel();
    _pollInFlight = false;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _pollOnce(requestToken);
    });
  }

  Future<void> _pollOnce(String requestToken) async {
    if (_pollInFlight) return;
    final cur = state;
    if (cur is! AuthUnauthenticated || cur.isCompletingSync) return;

    _pollInFlight = true;
    try {
      // Approval already granted earlier; only the profile/sync step is left. The token
      // is consumed, so never poll it again — retry with the issued session instead.
      final issued = _pendingSessionId;
      if (issued != null) {
        await _completeAuthentication(issued);
        return;
      }

      // Stale (unapproved) tokens expire after 60 min — silently swap in a fresh one.
      final created = _tokenCreatedAt;
      if (created != null &&
          DateTime.now().difference(created) > TmdbRepository.kPendingAuthMaxAge) {
        _pollInFlight = false;
        await retryTokenGeneration();
        return;
      }

      final sessionId = await _tmdbRepo.tryCreateSession(
        requestToken,
        cancelToken: _cancelToken,
      );
      if (sessionId != null && sessionId.isNotEmpty) {
        _pendingSessionId = sessionId;
        // Persist the issued session right away: if the process dies before the profile
        // fetch completes, the next launch finishes the login instead of wasting it.
        await _tmdbRepo.savePendingAuth(
          requestToken: requestToken,
          createdAt: _tokenCreatedAt ?? DateTime.now(),
          sessionId: sessionId,
        );
        await _completeAuthentication(sessionId);
      }
    } catch (_) {
      // Transient network hiccups during polling are ignored so the loop continues.
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _completeAuthentication(String sessionId) async {
    final cur = state;
    if (cur is AuthUnauthenticated) {
      state = cur.copyWith(
        isPollingApproval: false,
        isCompletingSync: true,
        clearError: true,
      );
    }
    try {
      final profile = await _tmdbRepo.fetchAndStoreAccountProfile(
        sessionId,
        cancelToken: _cancelToken,
      );
      _pollTimer?.cancel();
      _pollTimer = null;
      String? syncError;
      try {
        await _syncAccount(
          pushLocal: true,
          cancelToken: _cancelToken,
          throwOnError: true,
        );
      } catch (_) {
        // Retry once after browser-return socket warmup before entering app.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        try {
          await _syncAccount(
            pushLocal: true,
            cancelToken: _cancelToken,
            throwOnError: true,
          );
        } catch (e) {
          syncError = _tmdbRepo.lastSyncError ?? e.toString();
        }
      }
      await _tmdbRepo.clearPendingAuth();
      _pendingSessionId = null;
      _activeRequestToken = null;
      state = AuthAuthenticated(
        sessionId: sessionId,
        profile: profile,
        syncError: syncError,
      );
      unawaited(ref.read(homeControllerProvider.notifier).refresh());
      unawaited(
        ref.read(personalizedRowsControllerProvider.notifier).loadAll(),
      );
    } catch (_) {
      // Keep `_pendingSessionId`; the still-running timer retries the profile step.
      final latest = state;
      if (latest is AuthUnauthenticated) {
        state = latest.copyWith(
          isCompletingSync: false,
          isPollingApproval: true,
          errorMessage: 'Approval received. Finishing TMDB sync, retrying...',
        );
      }
    }
  }

  /// Opens the TMDB approval URL in the user's external browser when they tap
  /// the primary `"Sign in"` button on Screen 2.
  Future<bool> openBrowserForSignIn() async {
    var cur = state;
    if (cur is AuthUnauthenticated &&
        (cur.approvalUrl == null || cur.approvalUrl!.isEmpty) &&
        !cur.isPreparingToken) {
      await retryTokenGeneration();
      cur = state;
    }
    if (cur is! AuthUnauthenticated) return false;
    final url = cur.approvalUrl;
    if (url == null || url.isEmpty) return false;

    // Trigger an immediate check shortly after returning/clicking as well.
    if (cur.requestToken != null) {
      unawaited(_pollOnce(cur.requestToken!));
    }

    return launchExternalUrl(url);
  }

  /// Manually triggers a full Watchlist + Ratings sync with TMDB.
  /// Returns true if TMDB confirmed the sync without errors.
  Future<bool> syncNow() async {
    final cur = state;
    if (cur is! AuthAuthenticated || cur.isSyncing) return false;
    state = cur.copyWith(isSyncing: true, clearSyncError: true);
    var ok = true;
    String? err;
    try {
      await _syncAccount(throwOnError: true);
      unawaited(
        ref.read(personalizedRowsControllerProvider.notifier).loadAll(),
      );
    } catch (e) {
      ok = false;
      err = _tmdbRepo.lastSyncError ?? e.toString();
    } finally {
      final after = state;
      if (after is AuthAuthenticated) {
        state = after.copyWith(
          isSyncing: false,
          syncError: ok ? null : err,
          clearSyncError: ok,
        );
      }
    }
    return ok;
  }

  /// Reconnects an expired TMDB session in-place while preserving every local
  /// My List item, Like, Dislike, and pending mutation so they push on sign-in.
  Future<void> reconnectSession() async {
    await _tmdbRepo.prepareSessionReconnect();
    await proceedToSignIn();
  }

  /// Signs out of TMDB and returns to Screen 1 (`Netflix · Welcome`).
  Future<void> logout() async {
    _resetPendingState();
    await _tmdbRepo.logout();
    state = const AuthUnauthenticated(step: AuthOnboardingStep.welcome);
  }

  /// Launches [url] in the system browser via the native Android `openflix/launcher`
  /// channel or desktop OS opener.
  static Future<bool> launchExternalUrl(String url) async {
    try {
      final launched = await _launcherChannel.invokeMethod<bool>(
        'openUrl',
        {'url': url},
      );
      if (launched == true) return true;
    } catch (_) {}

    try {
      if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [url]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [url]);
        return res.exitCode == 0;
      } else if (Platform.isWindows) {
        final res = await Process.run('cmd', ['/c', 'start', '', url]);
        return res.exitCode == 0;
      }
    } catch (_) {}
    return false;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
