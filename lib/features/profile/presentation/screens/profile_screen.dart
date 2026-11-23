import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_links.dart';
import '../../../../core/errors/user_error.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../addons/presentation/screens/addons_screen.dart';
import '../../../addons/presentation/widgets/addons_ui_kit.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../../my_list/presentation/controllers/my_list_controller.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../../preferences/presentation/widgets/language_setup_sheet.dart';
import 'liked_screen.dart';

const _kCardBg = Color(0xFF131620);
const _kCardBorder = Color(0x0AFFFFFF); // rgba(255, 255, 255, 0.04)
const _kStatLabelColor = Color(0xFF8B92A5);
const _kDisconnectBg = Color(0x66FF0360); // rgba(255, 3, 96, 0.40)
const _kDisconnectBorder = Color(0xFF923741);
const _kAddonsBg = Color(0xFF1B202E);

const _kBookmarkIconSvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M14.1665 2.5H5.83317C4.9165 2.5 4.1665 3.25 4.1665 4.16667V17.5L9.99984 15L15.8332 17.5V4.16667C15.8332 3.25 15.0832 2.5 14.1665 2.5V2.5" fill="white"/>'
    '</svg>';

const _kThumbsUpIconSvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M0.833496 17.5H4.16683V7.49998H0.833496V17.5V17.5M19.1668 8.33331C19.1668 7.41665 18.4168 6.66665 17.5002 6.66665H12.2418L13.0335 2.85831L13.0585 2.59165C13.0585 2.24998 12.9168 1.93331 12.6918 1.70831L11.8085 0.833313L6.32516 6.32498C6.01683 6.62498 5.8335 7.04165 5.8335 7.49998V15.8333C5.8335 16.75 6.5835 17.5 7.50016 17.5H15.0002C15.6918 17.5 16.2835 17.0833 16.5335 16.4833L19.0502 10.6083C19.1252 10.4166 19.1668 10.2166 19.1668 9.99998V8.33331V8.33331" fill="white"/>'
    '</svg>';

const _kSyncIconSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M7.99984 2.66663V0.666626L5.33317 3.33329L7.99984 5.99996V3.99996C10.2065 3.99996 11.9998 5.79329 11.9998 7.99996C11.9998 8.67329 11.8332 9.31329 11.5332 9.86663L12.5065 10.84C13.0265 10.02 13.3332 9.04663 13.3332 7.99996C13.3332 5.05329 10.9465 2.66663 7.99984 2.66663V2.66663M7.99984 12C5.79317 12 3.99984 10.2066 3.99984 7.99996C3.99984 7.32663 4.1665 6.68663 4.4665 6.13329L3.49317 5.15996C2.97317 5.97996 2.6665 6.95329 2.6665 7.99996C2.6665 10.9466 5.05317 13.3333 7.99984 13.3333V15.3333L10.6665 12.6666L7.99984 9.99996V12V12" fill="black"/>'
    '</svg>';

const _kLogoutIconSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M6 14H3.33333C2.59745 14 2 13.4026 2 12.6667V3.33333C2 2.59745 2.59745 2 3.33333 2H6" stroke="white" stroke-width="1.46667" stroke-linecap="round" stroke-linejoin="round"/>'
    '<path d="M10.6665 11.3333L13.9998 7.99996L10.6665 4.66663" stroke="white" stroke-width="1.46667" stroke-linecap="round" stroke-linejoin="round"/>'
    '<path d="M14 8H6" stroke="white" stroke-width="1.46667" stroke-linecap="round" stroke-linejoin="round"/>'
    '</svg>';

const _kAddonsIconSvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M9.05484 1.68828C10.0032 1.82578 10.7473 2.64245 10.8082 3.59745C10.8207 3.79578 10.8057 3.97245 10.764 4.16661C10.7182 4.38328 10.5382 4.62411 10.6748 4.84245C10.7407 4.94911 10.8365 4.98745 10.9557 4.99995H12.4998C13.1673 5.02245 13.7898 5.25411 14.2673 5.73245C14.7457 6.20995 14.9773 6.83245 14.9998 7.49995V9.04411C15.0098 9.13411 15.0165 9.18328 15.0748 9.25411C15.2407 9.45495 15.4565 9.34995 15.6565 9.28495C15.8107 9.23411 15.954 9.20578 16.119 9.19328C16.4923 9.16546 16.8661 9.2404 17.1998 9.40995C18.8173 10.2274 18.6548 12.6024 16.9457 13.1983C16.6815 13.2899 16.3982 13.3283 16.119 13.3066C15.9617 13.2952 15.8063 13.2644 15.6565 13.2149C15.4257 13.1399 15.1415 13.0233 15.0198 13.3408L14.9998 13.4558V15.8333C14.9582 17.0849 14.109 18.1391 12.839 18.3108L12.4998 18.3333H10.9223C10.8332 18.3233 10.7873 18.3183 10.7165 18.2616C10.4665 18.0658 10.6482 17.7483 10.6682 17.4999C10.6823 17.3191 10.674 17.1499 10.639 16.9716C10.5401 16.4873 10.2602 16.0589 9.85635 15.7739C9.45251 15.4888 8.95515 15.3685 8.46567 15.4374C8.07339 15.4984 7.70923 15.6782 7.42225 15.9525C7.13527 16.2268 6.93928 16.5825 6.86067 16.9716C6.82657 17.1455 6.81675 17.3233 6.8315 17.4999C6.85234 17.7683 7.059 18.1766 6.68984 18.3141L6.57734 18.3333H4.1665C3.90984 18.3249 3.74984 18.3116 3.5015 18.2441C2.38817 17.9383 1.70484 16.9633 1.6665 15.8333V13.4224C1.6765 13.3333 1.6815 13.2874 1.73817 13.2166C1.934 12.9666 2.2515 13.1483 2.49984 13.1683C2.68067 13.1824 2.84984 13.1741 3.02817 13.1391C3.46476 13.0504 3.85756 12.8143 4.14069 12.4703C4.42382 12.1263 4.58005 11.6954 4.58317 11.2499C4.58005 10.8044 4.42382 10.3736 4.14069 10.0296C3.85756 9.68563 3.46476 9.44949 3.02817 9.36078C2.85425 9.32668 2.67645 9.31686 2.49984 9.33161C2.2515 9.35161 1.934 9.53328 1.73817 9.28328C1.6815 9.21161 1.6765 9.16661 1.6665 9.07745V7.49995C1.67484 7.24328 1.68817 7.08328 1.75567 6.83495C1.86984 6.41995 2.094 6.03661 2.399 5.73245C2.8765 5.25411 3.499 5.02245 4.1665 4.99995H6.544C6.634 4.98995 6.68317 4.98328 6.754 4.92495C7.0065 4.71661 6.78734 4.40911 6.73567 4.16661C6.69381 3.97998 6.67893 3.7883 6.6915 3.59745C6.76734 2.40495 7.87567 1.51828 9.05484 1.68828Z" fill="white"/>'
    '</svg>';

const _kDiscordIconSvg =
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M19.27 5.33C17.94 4.71 16.5 4.26 15 4a.09.09 0 0 0-.07.03c-.18.33-.39.76-.53 1.09a16.09 16.09 0 0 0-4.8 0c-.14-.34-.35-.76-.54-1.09-.01-.02-.04-.03-.07-.03-1.5.26-2.93.71-4.27 1.33-.01 0-.02.01-.03.02-2.72 4.07-3.47 8.03-3.1 11.95 0 .02.01.04.03.05 1.8 1.32 3.53 2.12 5.24 2.65.03.01.06 0 .07-.02.4-.55.76-1.13 1.07-1.74.02-.04 0-.08-.04-.09-.57-.22-1.11-.48-1.64-.78-.04-.02-.04-.08-.01-.11.11-.08.22-.17.33-.25.02-.02.05-.02.07-.01 3.44 1.57 7.15 1.57 10.55 0 .02-.01.05-.01.07.01.11.09.22.17.33.26.04.03.04.09-.01.11-.52.31-1.07.56-1.64.78-.04.01-.05.06-.04.09.32.61.68 1.19 1.07 1.74.02.03.05.03.08.02 1.72-.53 3.45-1.33 5.25-2.65.02-.01.03-.03.03-.05.44-4.53-.73-8.46-3.1-11.95-.01-.01-.02-.02-.04-.02ZM8.52 14.91c-1.03 0-1.89-.95-1.89-2.12s.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12 0 1.17-.84 2.12-1.89 2.12Zm6.97 0c-1.03 0-1.89-.95-1.89-2.12s.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12 0 1.17-.83 2.12-1.89 2.12Z" fill="white"/>'
    '</svg>';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  TmdbRepository? _repo;
  String _installedVersion = '1.1.0';
  bool _isCheckingUpdate = false;
  String? _updateStatusMessage;
  bool _updateStatusIsError = false;

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadInstalledVersion();
  }

  Future<void> _loadInstalledVersion() async {
    final version = await UpdateService.instance.getInstalledVersion();
    if (mounted) {
      setState(() => _installedVersion = version);
    }
  }

  Future<void> _onJoinDiscordPressed() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(AppLinks.discordInviteUrl);
    var launched = false;
    try {
      launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      AppToast.show(
        context,
        message: "Couldn't open Discord right now.",
        isError: true,
      );
    }
  }

  Future<void> _onCheckForUpdatesPressed() async {
    if (_isCheckingUpdate) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isCheckingUpdate = true;
      _updateStatusMessage = null;
      _updateStatusIsError = false;
    });

    final result = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;

    setState(() {
      _isCheckingUpdate = false;
      _installedVersion = result.installedVersion;
    });

    if (result.status == UpdateCheckStatus.updateAvailable &&
        result.updateInfo != null) {
      await showUpdateBottomSheet(context, info: result.updateInfo!);
      return;
    }

    final isErr = result.status == UpdateCheckStatus.error;
    final msg =
        isErr ? "Couldn't check for updates right now." : "You're on the latest version";
    setState(() {
      _updateStatusMessage = msg;
      _updateStatusIsError = isErr;
    });

    AppToast.show(
      context,
      message: msg,
      isError: isErr,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = ref.read(tmdbRepositoryProvider);
    if (!identical(_repo, repo)) {
      _repo?.removeMyListListener(_onRepoChanged);
      _repo = repo;
      _repo!.addMyListListener(_onRepoChanged);
    }
  }

  @override
  void dispose() {
    _repo?.removeMyListListener(_onRepoChanged);
    super.dispose();
  }

  Future<void> _onSyncPressed(bool isExpired) async {
    HapticFeedback.lightImpact();
    if (isExpired) {
      await ref.read(authControllerProvider.notifier).reconnectSession();
      return;
    }
    final ok = await ref.read(authControllerProvider.notifier).syncNow();
    if (!mounted) return;
    final repoAfter = ref.read(tmdbRepositoryProvider);
    final expiredAfter = repoAfter.isSessionExpired;
    if (ok) {
      AppToast.show(
        context,
        message: 'Synced Watchlist & Ratings with TMDB',
      );
      return;
    }
    if (expiredAfter) {
      AppToast.showError(
        context,
        UserError.authRequired(),
        actionLabel: 'Sign In',
        onAction: () =>
            ref.read(authControllerProvider.notifier).reconnectSession(),
      );
      return;
    }
    AppToast.showError(
      context,
      UserError.from(
        repoAfter.lastSyncError,
        fallbackType: UserErrorType.offline,
        logTag: 'ProfileScreen.tmdbSync',
      ),
    );
  }

  void _openMyListTab() {
    HapticFeedback.selectionClick();
    ref.read(activeTabProvider.notifier).state = PixelTab.myList;
  }

  void _openLikedScreen(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const LikedScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final authState = ref.watch(authControllerProvider);
    final myListState = ref.watch(myListControllerProvider);
    final tmdbRepo = ref.watch(tmdbRepositoryProvider);
    final likedCount = tmdbRepo.getCachedLikedMetas().length;
    final myListCount = myListState.items.length;
    final addonsCount = ref.watch(installedAddonsCountProvider);
    final prefs =
        ref.watch(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    final primaryLang = languageOptionForCode(prefs.primaryLanguage);
    final fallbackLang = languageOptionForCode(prefs.fallbackLanguage);
    final pendingCount = tmdbRepo.pendingSyncCount;
    final rawSyncErr = !tmdbRepo.lastSyncSucceeded
        ? (tmdbRepo.lastSyncError ??
            (authState is AuthAuthenticated ? authState.syncError : null))
        : null;
    final isExpired = tmdbRepo.isSessionExpired ||
        (rawSyncErr != null && rawSyncErr.contains('status code of 401'));
    final syncErr = isExpired
        ? 'TMDB session expired. Tap Reconnect below to back up your My List & Likes.'
        : rawSyncErr;

    if (authState is! AuthAuthenticated) {
      return const ColoredBox(color: AppColors.background);
    }

    final profile = authState.profile;
    final avatarUrl = profile.avatarUrl;

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 120.h),
          children: [
            Text(
              'Profile',
              style: GoogleFonts.inter(
                fontSize: 30.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.75,
                height: 36 / 30,
              ),
            ),
            SizedBox(height: 20.h),

            // User Profile Card (Figma frame 169:22)
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: _kCardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64.r,
                    height: 64.r,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 6,
                          offset: Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? FallbackNetworkImage(
                            urls: [avatarUrl],
                            memWidth: 64.r,
                            memHeight: 64.r,
                            fallback: _InitialsAvatar(name: profile.displayName),
                          )
                        : _InitialsAvatar(name: profile.displayName),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 28 / 20,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            // Stats Grid (My List & Liked)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'My List',
                      value: '$myListCount',
                      iconSvg: _kBookmarkIconSvg,
                      onTap: _openMyListTab,
                    ),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: _MetricTile(
                      label: 'Liked',
                      value: '$likedCount',
                      iconSvg: _kThumbsUpIconSvg,
                      onTap: () => _openLikedScreen(context),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            if (pendingCount > 0 || syncErr != null) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: _kCardBg,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: syncErr != null
                        ? const Color(0x66923741)
                        : const Color(0x14FFFFFF),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      syncErr != null
                          ? Icons.sync_problem_rounded
                          : Icons.cloud_upload_outlined,
                      size: 18.r,
                      color: syncErr != null
                          ? const Color(0xFFFF8F95)
                          : _kStatLabelColor,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        syncErr ??
                            '$pendingCount change${pendingCount == 1 ? '' : 's'} queued to sync with TMDB',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: syncErr != null
                              ? const Color(0xFFFF8F95)
                              : _kStatLabelColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
            ],

            // Primary Action: Sync with TMDB
            AnimatedOpacity(
              opacity: authState.isSyncing ? 0.72 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: const Cubic(0.22, 1, 0.36, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: authState.isSyncing
                        ? null
                        : () => _onSyncPressed(isExpired),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 14.h,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: isExpired ? _kDisconnectBorder : _kCardBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (authState.isSyncing)
                            SizedBox(
                              width: 16.r,
                              height: 16.r,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          else if (isExpired)
                            Icon(
                              Icons.link_rounded,
                              size: 16.r,
                              color: Colors.black,
                            )
                          else
                            SvgPicture.string(
                              _kSyncIconSvg,
                              width: 16.r,
                              height: 16.r,
                            ),
                          SizedBox(width: 8.w),
                          Flexible(
                            child: Text(
                              authState.isSyncing
                                  ? 'Syncing with TMDB...'
                                  : (isExpired
                                      ? 'Reconnect & Sync TMDB Account'
                                      : 'Sync with TMDB'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                height: 20 / 14,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // Secondary Destructive Action: Disconnect TMDB Account
            Material(
              color: _kDisconnectBg,
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ref.read(authControllerProvider.notifier).logout();
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: _kDisconnectBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.string(
                        _kLogoutIconSvg,
                        width: 16.r,
                        height: 16.r,
                      ),
                      SizedBox(width: 10.w),
                      Flexible(
                        child: Text(
                          'Disconnect TMDB Account',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            height: 20 / 14,
                            letterSpacing: 0.35,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // Addons Action Button (Figma frame 169:278)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Material(
                color: _kAddonsBg,
                borderRadius: BorderRadius.circular(12.r),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push<void>(
                      addonsRoute<void>(const AddonsScreen()),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.h,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: _kCardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.string(
                          _kAddonsIconSvg,
                          width: 20.r,
                          height: 20.r,
                        ),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Text(
                            'Addons',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              height: 20 / 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (addonsCount > 0) ...[
                          SizedBox(width: 8.w),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x14FFFFFF),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0x2EFFFFFF),
                              ),
                            ),
                            child: Text(
                              '$addonsCount',
                              style: GoogleFonts.inter(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // Languages & Playback Preferences
            Material(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showLanguageSetupSheet(context);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: _kCardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 18.r,
                        color: Colors.white,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          'Watch Languages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 9.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B202E),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x1EFFFFFF)),
                        ),
                        child: Text(
                          '${primaryLang.name} · ${fallbackLang.name}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFE4E4E7),
                          ),
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18.r,
                        color: _kStatLabelColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 24.h),

            // Section: Community & App
            Padding(
              padding: EdgeInsets.only(left: 4.w, bottom: 10.h),
              child: Text(
                'Community & App',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: _kStatLabelColor,
                  letterSpacing: 0.4,
                  height: 1.25,
                ),
              ),
            ),

            // 1. Join Discord Community
            Material(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _onJoinDiscordPressed,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      SvgPicture.string(
                        _kDiscordIconSvg,
                        width: 19.r,
                        height: 19.r,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          'Join Discord Community',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 16.r,
                        color: _kStatLabelColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(height: 12.h),

            // 2. Check for Updates
            Material(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(12.r),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _isCheckingUpdate ? null : _onCheckForUpdatesPressed,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 14.h,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (_isCheckingUpdate)
                            SizedBox(
                              width: 18.r,
                              height: 18.r,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          else
                            Icon(
                              Icons.system_update_alt_rounded,
                              size: 18.r,
                              color: Colors.white,
                            ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              _isCheckingUpdate
                                  ? 'Checking for Updates...'
                                  : 'Check for Updates',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B202E),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0x1EFFFFFF),
                              ),
                            ),
                            child: Text(
                              'v$_installedVersion',
                              style: GoogleFonts.inter(
                                fontSize: 11.5.sp,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFE4E4E7),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 4.w),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18.r,
                            color: _kStatLabelColor,
                          ),
                        ],
                      ),
                      if (_updateStatusMessage != null) ...[
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.only(left: 28.w),
                          child: Text(
                            _updateStatusMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                              color: _updateStatusIsError
                                  ? const Color(0xFFFF8F95)
                                  : _kStatLabelColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'T';
    return ColoredBox(
      color: const Color(0xFF261834),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.inter(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.iconSvg,
    required this.onTap,
  });

  final String label;
  final String value;
  final String iconSvg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(16.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: 116.h),
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: _kCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.string(
                iconSvg,
                width: 20.r,
                height: 20.r,
              ),
              SizedBox(height: 21.h),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.0,
                  letterSpacing: -0.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w400,
                  color: _kStatLabelColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
