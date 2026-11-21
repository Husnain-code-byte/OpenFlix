import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../../preferences/presentation/widgets/language_setup_sheet.dart';
import '../controllers/auth_controller.dart';

/// Checkmark SVG from Figma frame `133:21` ("Netflix · Welcome").
const _kWelcomeCheckSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 12L9 18L22 3" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="#ED0011"/></svg>';

/// External link SVG from Figma frame `133:21` ("Connect TMDB" button).
const _kExternalLinkSvg =
    '<svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M19.25 9.16667V2.75H12.8333M19.25 2.75L10.0833 11.9167M9.16667 2.75H2.75V19.25H19.25V12.8333" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white"/></svg>';

/// Copy icon SVG (`akar-icons:copy`) from Figma frame `133:26` ("Netflix · Sign in").
const _kCopyLinkSvg =
    '<svg width="30" height="29" viewBox="0 0 30 29" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 18.125H17.5M10 12.0833H20M10 6.04167H12.5M7.5 4.83333H5C4.33696 4.83333 3.70107 5.08795 3.23223 5.54116C2.76339 5.99437 2.5 6.60906 2.5 7.25V21.75C2.5 22.3909 2.76339 23.0056 3.23223 23.4588C3.70107 23.9121 4.33696 24.1667 5 24.1667H20C20.663 24.1667 21.2989 23.9121 21.7678 23.4588C22.2366 23.0056 22.5 22.3909 22.5 21.75V7.25C22.5 6.60906 22.2366 5.99437 21.7678 5.54116C21.2989 5.08795 20.663 4.83333 20 4.83333H17.5M7.5 4.83333C7.5 3.55144 8.02678 2.32206 8.96447 1.41563C9.90215 0.509208 11.1739 0 12.5 0C13.8261 0 15.0979 0.509208 16.0355 1.41563C16.9732 2.32206 17.5 3.55144 17.5 4.83333M7.5 4.83333C7.5 5.47427 7.76339 6.08896 8.23223 6.54218C8.70107 6.99539 9.33696 7.25 10 7.25H15C15.663 7.25 16.2989 6.99539 16.7678 6.54218C17.2366 6.08896 17.5 5.47427 17.5 4.83333" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" stroke="white"/></svg>';

/// Copied confirmation checkmark SVG.
const _kCopiedCheckSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 12.5L9.5 18L20 6.5" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" stroke="white"/></svg>';

/// Curated showcase posters for the 3-column alternating scrolling wall.
/// Each entry uses `betterPosterUrl(imdbId)` (`btttr.cc`) as primary artwork and
/// TMDB `w342` as fallback, matching the Details screen's "More Like This" cards.
final List<List<MetaModel>> _kPosterWallColumns = [
  // Column 1 (Scrolls Upward)
  [
    MetaModel(
      id: 'tt15239678',
      type: 'movie',
      name: 'Dune: Part Two',
      poster: betterPosterUrl('tt15239678'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg',
      releaseInfo: '2024',
    ),
    MetaModel(
      id: 'tt0903747',
      type: 'series',
      name: 'Breaking Bad',
      poster: betterPosterUrl('tt0903747'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/ztkUQFLlC19CCMYHW9o1zWhJRNq.jpg',
      releaseInfo: '2008',
    ),
    MetaModel(
      id: 'tt15398776',
      type: 'movie',
      name: 'Oppenheimer',
      poster: betterPosterUrl('tt15398776'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg',
      releaseInfo: '2023',
    ),
    MetaModel(
      id: 'tt1190634',
      type: 'series',
      name: 'The Boys',
      poster: betterPosterUrl('tt1190634'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/2zmTngn1tYC1AvfnrFLhxeD82hz.jpg',
      releaseInfo: '2019',
    ),
    MetaModel(
      id: 'tt0816692',
      type: 'movie',
      name: 'Interstellar',
      poster: betterPosterUrl('tt0816692'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg',
      releaseInfo: '2014',
    ),
    MetaModel(
      id: 'tt11280740',
      type: 'series',
      name: 'Severance',
      poster: betterPosterUrl('tt11280740'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/pPHpeI2X1qEd1CS1SeyrdhZ4qnT.jpg',
      releaseInfo: '2022',
    ),
  ],
  // Column 2 (Scrolls Downward — opposite direction to Column 1)
  [
    MetaModel(
      id: 'tt1877830',
      type: 'movie',
      name: 'The Batman',
      poster: betterPosterUrl('tt1877830'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/74xTEgt7R36Fpooo50r9T25onhq.jpg',
      releaseInfo: '2022',
    ),
    MetaModel(
      id: 'tt4574334',
      type: 'series',
      name: 'Stranger Things',
      poster: betterPosterUrl('tt4574334'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/uOOtwVbSr4QDjAGIifLDwpb2Pdl.jpg',
      releaseInfo: '2016',
    ),
    MetaModel(
      id: 'tt9362722',
      type: 'movie',
      name: 'Spider-Man: Across the Spider-Verse',
      poster: betterPosterUrl('tt9362722'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/8Vt6mWEReuy4Of61Lnj5Xj704m8.jpg',
      releaseInfo: '2023',
    ),
    MetaModel(
      id: 'tt3581920',
      type: 'series',
      name: 'The Last of Us',
      poster: betterPosterUrl('tt3581920'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/uKvVjHNqB5VmOrdxqAt2F7J78ED.jpg',
      releaseInfo: '2023',
    ),
    MetaModel(
      id: 'tt1856101',
      type: 'movie',
      name: 'Blade Runner 2049',
      poster: betterPosterUrl('tt1856101'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/gajva2L0rPYkEWjzgFlBXCAVBE5.jpg',
      releaseInfo: '2017',
    ),
    MetaModel(
      id: 'tt11126994',
      type: 'series',
      name: 'Arcane',
      poster: betterPosterUrl('tt11126994'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/fqldf2t8ztc9aiwn3k6mlX3tvRT.jpg',
      releaseInfo: '2021',
    ),
  ],
  // Column 3 (Scrolls Upward — opposite direction to Column 2)
  [
    MetaModel(
      id: 'tt0468569',
      type: 'movie',
      name: 'The Dark Knight',
      poster: betterPosterUrl('tt0468569'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/qJ2tW6WMUDux911r6m7haRef0WH.jpg',
      releaseInfo: '2008',
    ),
    MetaModel(
      id: 'tt11198330',
      type: 'series',
      name: 'House of the Dragon',
      poster: betterPosterUrl('tt11198330'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg',
      releaseInfo: '2022',
    ),
    MetaModel(
      id: 'tt1745960',
      type: 'movie',
      name: 'Top Gun: Maverick',
      poster: betterPosterUrl('tt1745960'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/62HCnUTziyWcpDaBO2i1DX17ljH.jpg',
      releaseInfo: '2022',
    ),
    MetaModel(
      id: 'tt14452776',
      type: 'series',
      name: 'The Bear',
      poster: betterPosterUrl('tt14452776'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/sHFlbKS3WLqMnp9t2ghADIJFnuQ.jpg',
      releaseInfo: '2022',
    ),
    MetaModel(
      id: 'tt1375666',
      type: 'movie',
      name: 'Inception',
      poster: betterPosterUrl('tt1375666'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg',
      releaseInfo: '2010',
    ),
    MetaModel(
      id: 'tt2788316',
      type: 'series',
      name: 'Shōgun',
      poster: betterPosterUrl('tt2788316'),
      posterFallback: 'https://image.tmdb.org/t/p/w342/7O4iVfOMQmdCSxhOg1WnzG1AgYT.jpg',
      releaseInfo: '2024',
    ),
  ],
];

/// Mandatory Two-Step TMDB Authentication & Onboarding Gate implementing:
/// - **Screen 1 (`Netflix · Welcome`, Figma frame `133:21`)**
/// - **Screen 2 (`Netflix · Sign in`, Figma frame `133:26`)**
class TmdbAuthScreen extends ConsumerStatefulWidget {
  const TmdbAuthScreen({super.key});

  @override
  ConsumerState<TmdbAuthScreen> createState() => _TmdbAuthScreenState();
}

class _TmdbAuthScreenState extends ConsumerState<TmdbAuthScreen>
    with SingleTickerProviderStateMixin {
  static const Color _kCanvasColor = Color(0xFF170D20);
  static const Color _kGlowMidColor = Color(0xFF2A0D22);
  static const Color _kGlowBottomColor = Color(0xFF710D24);
  static const Color _kWelcomeRed = Color(0xFFED0011);
  static const Color _kSignInRed = Color(0xFFE50914);
  static const Color _kLinkFieldBg = Color(0xFF333333);

  late final AnimationController _wallController;
  bool _copiedRecently = false;

  @override
  void initState() {
    super.initState();
    _wallController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();
  }

  @override
  void dispose() {
    _wallController.dispose();
    super.dispose();
  }

  Future<void> _copyApprovalLink(String url) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copiedRecently = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Verification link copied to clipboard',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF241630),
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0x2EFFFFFF)),
          ),
        ),
      );
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copiedRecently = false);
    });
  }

  Future<void> _handleSignInTap(AuthUnauthenticated authState) async {
    HapticFeedback.lightImpact();
    final controller = ref.read(authControllerProvider.notifier);
    final opened = await controller.openBrowserForSignIn();
    if (!opened && mounted && authState.approvalUrl != null) {
      await _copyApprovalLink(authState.approvalUrl!);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final authState = ref.watch(authControllerProvider);
    final unauth = authState is AuthUnauthenticated
        ? authState
        : const AuthUnauthenticated(step: AuthOnboardingStep.welcome);
    final isSignInStep = unauth.step == AuthOnboardingStep.signIn;

    return PopScope(
      canPop: !isSignInStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isSignInStep) {
          ref.read(authControllerProvider.notifier).backToWelcome();
        }
      },
      child: Scaffold(
        backgroundColor: _kCanvasColor,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = constraints.maxHeight;
            // Matches Figma's 440px top poster wall on reference device while adapting gracefully
            // to shorter or taller screens so the bottom CTA never clips.
            final wallHeight = (maxHeight * 0.52).clamp(240.h, 440.h);
            final glowTop = (wallHeight - 19.h).clamp(200.h, 421.h);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Base dark purple-black canvas (#170D20)
                const ColoredBox(color: _kCanvasColor),

                // Figma bottom crimson gradient glow
                Positioned(
                  left: 0,
                  right: 0,
                  top: glowTop,
                  bottom: 0,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, 0.55, 1.0],
                        colors: [
                          _kCanvasColor,
                          _kGlowMidColor,
                          _kGlowBottomColor,
                        ],
                      ),
                    ),
                  ),
                ),

                // Top 3-column alternating scrolling poster wall (440px in Figma)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: wallHeight,
                  child: _ScrollingPosterWall(
                    animation: _wallController,
                    height: wallHeight,
                  ),
                ),

                // Foreground content area
                SafeArea(
                  top: true,
                  bottom: true,
                  child: Column(
                    children: [
                      // Top bar (Back button on Screen 2)
                      SizedBox(
                        height: 48.h,
                        child: isSignInStep
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 12.w),
                                  child: IconButton(
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(authControllerProvider.notifier)
                                          .backToWelcome();
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0x88170D20),
                                      shape: const CircleBorder(
                                        side: BorderSide(color: Color(0x22FFFFFF)),
                                      ),
                                    ),
                                    icon: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 18.r,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'Back',
                                  ),
                                ),
                              )
                            : null,
                      ),

                      const Spacer(),

                      // Animated transition between Screen 1 (Welcome) and Screen 2 (Sign in)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
                        switchOutCurve: const Cubic(0.22, 1.0, 0.36, 1.0),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: isSignInStep
                            ? _buildSignInPanel(context, unauth)
                            : _buildWelcomePanel(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Screen 1 (`Netflix · Welcome`, Figma frame `133:21`):
  /// - Headline: `"Ready for endless\nentertainment?"`
  /// - 3 red-checkmark benefit rows with professionalized, future-safe copy
  /// - `"Connect TMDB"` button (`#ED0011`, height `48`, radius `4`) + external-link icon
  Widget _buildWelcomePanel(BuildContext context) {
    return Padding(
      key: const ValueKey('welcome_step'),
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 364.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ready for endless\nentertainment?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 30.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 36 / 30,
                letterSpacing: -0.6,
              ),
            ),
            SizedBox(height: 24.h),
            const _WelcomeBenefitRow(
              text: 'Sync your Watchlist seamlessly across TMDB and OpenFlix',
            ),
            SizedBox(height: 16.h),
            const _WelcomeBenefitRow(
              text: 'Tailored recommendations powered by your likes and ratings',
            ),
            SizedBox(height: 16.h),
            const _WelcomeBenefitRow(
              text: 'One-time browser authorization—no passwords stored in-app',
            ),
            SizedBox(height: 28.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: Material(
                color: _kWelcomeRed,
                borderRadius: BorderRadius.circular(4.r),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(authControllerProvider.notifier).proceedToSignIn();
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'Connect TMDB',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        SvgPicture.string(
                          _kExternalLinkSvg,
                          width: 22.r,
                          height: 22.r,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Consumer(
              builder: (context, ref, _) {
                final prefs = ref
                        .watch(playbackPreferencesControllerProvider)
                        .valueOrNull ??
                    const PlaybackPreferences();
                final primaryOpt =
                    languageOptionForCode(prefs.primaryLanguage);
                final fallbackOpt =
                    languageOptionForCode(prefs.fallbackLanguage);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    showLanguageSetupSheet(context);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 10.h,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x33000000),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: const Color(0x28FFFFFF)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.translate_rounded,
                          size: 16.r,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Text(
                            prefs.hasCompletedLanguageSetup
                                ? 'Languages: ${primaryOpt.name} → ${fallbackOpt.name}'
                                : 'Choose Watch & Fallback Languages',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16.r,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Screen 2 (`Netflix · Sign in`, Figma frame `133:26`):
  /// - Headline: `"Ready to watch?"`
  /// - Formalized, professional instruction copy
  /// - Primary `"Sign in"` button (`#E50914`, height `47`, radius `5`)
  /// - Link field (`#333333`, height `47`, radius `5`) + Copy button (`#E50914`, `63×47`)
  /// - Live auto-polling approval status & inline error recovery
  Widget _buildSignInPanel(BuildContext context, AuthUnauthenticated authState) {
    final approvalUrl = authState.approvalUrl ?? '';
    final hasUrl = approvalUrl.isNotEmpty;

    return Padding(
      key: const ValueKey('signin_step'),
      padding: EdgeInsets.fromLTRB(13.w, 0, 13.w, 24.h),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 364.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ready to watch?',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 30.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 36 / 30,
                letterSpacing: -0.6,
              ),
            ),
            SizedBox(height: 14.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Text(
                'Tap Sign in below to authorize OpenFlix in your browser, or copy the verification link into the browser where you are signed in to TMDB and select Allow.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.5.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xE0FFFFFF),
                  height: 1.48,
                ),
              ),
            ),
            SizedBox(height: 22.h),

            // Primary "Sign in" button (Figma: 364×47, #E50914, radius 5)
            SizedBox(
              width: double.infinity,
              height: 47.h,
              child: Material(
                color: _kSignInRed,
                borderRadius: BorderRadius.circular(5.r),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: authState.isCompletingSync
                      ? null
                      : () => _handleSignInTap(authState),
                  child: Center(
                    child: authState.isCompletingSync
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18.r,
                                height: 18.r,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Flexible(
                                child: Text(
                                  'Syncing TMDB Account...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 17.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Sign in',
                            style: GoogleFonts.inter(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16.h),

            // Link Field (#333333, 278×47) + Copy Link Button (#E50914, 63×47)
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 47.h,
                    decoration: BoxDecoration(
                      color: _kLinkFieldBg,
                      borderRadius: BorderRadius.circular(5.r),
                      border: Border.all(color: const Color(0x18FFFFFF)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(5.r),
                        onTap: hasUrl ? () => _copyApprovalLink(approvalUrl) : null,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14.w),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: authState.isPreparingToken
                                ? Container(
                                    height: 12.h,
                                    width: 190.w,
                                    decoration: BoxDecoration(
                                      color: const Color(0x22FFFFFF),
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                  )
                                : Text(
                                    hasUrl
                                        ? approvalUrl
                                        : 'Generating TMDB verification link...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5.sp,
                                      fontWeight: FontWeight.w600,
                                      color: hasUrl
                                          ? Colors.white
                                          : const Color(0x99FFFFFF),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                SizedBox(
                  width: 63.w,
                  height: 47.h,
                  child: Material(
                    color: _kSignInRed,
                    borderRadius: BorderRadius.circular(5.r),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: hasUrl
                          ? () => _copyApprovalLink(approvalUrl)
                          : () => ref
                              .read(authControllerProvider.notifier)
                              .retryTokenGeneration(),
                      child: Center(
                        child: _copiedRecently
                            ? SvgPicture.string(
                                _kCopiedCheckSvg,
                                width: 24.r,
                                height: 24.r,
                              )
                            : SvgPicture.string(
                                _kCopyLinkSvg,
                                width: 26.r,
                                height: 25.r,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Error / post-approval sync feedback bar
            _SignInStatusBanner(
              authState: authState,
              onRetry: () => ref
                  .read(authControllerProvider.notifier)
                  .retryTokenGeneration(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeBenefitRow extends StatelessWidget {
  const _WelcomeBenefitRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1.h),
          child: SvgPicture.string(
            _kWelcomeCheckSvg,
            width: 22.r,
            height: 22.r,
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xF0FFFFFF),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignInStatusBanner extends StatelessWidget {
  const _SignInStatusBanner({
    required this.authState,
    required this.onRetry,
  });

  final AuthUnauthenticated authState;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (authState.errorMessage != null) {
      return Padding(
        padding: EdgeInsets.only(top: 16.h),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: const Color(0x26E50914),
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(color: const Color(0x55E50914)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16.r,
                color: const Color(0xFFFF8A8F),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  authState.errorMessage!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFFD2D5),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Retry',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!authState.isCompletingSync) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7.r,
            height: 7.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF46D369),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF46D369).withValues(alpha: 0.6),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              'Approval detected! Syncing your Watchlist and ratings...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xB3FFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top 3-column infinite scrolling poster wall.
/// - Column 0 scrolls **Upward**
/// - Column 1 scrolls **Downward** (opposite to Column 0)
/// - Column 2 scrolls **Upward** (opposite to Column 1)
/// Each poster is decorated identically to the Details screen's "More Like This"
/// cards (`betterPosterUrl(imdbId)` + TMDB `w342` fallback, `AppDimens.posterRadius`,
/// `AppDimens.posterShadow`, subtle top-edge specular border).
class _ScrollingPosterWall extends StatelessWidget {
  const _ScrollingPosterWall({
    required this.animation,
    required this.height,
  });

  final Animation<double> animation;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = 12.w;
              final columnGap = 10.w;
              final verticalGap = 10.h;
              final availableWidth =
                  (constraints.maxWidth - horizontalPadding * 2 - columnGap * 2)
                      .clamp(180.0, 1200.0);
              final colWidth = availableWidth / 3;
              // Standard 2:3 poster aspect ratio matching PosterCard (113×170)
              final posterHeight = (colWidth * (170.0 / 113.0)).roundToDouble();

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: _AnimatedPosterColumn(
                        items: _kPosterWallColumns[0],
                        animation: animation,
                        posterWidth: colWidth,
                        posterHeight: posterHeight,
                        verticalGap: verticalGap,
                        scrollUp: true,
                      ),
                    ),
                    SizedBox(width: columnGap),
                    Expanded(
                      child: _AnimatedPosterColumn(
                        items: _kPosterWallColumns[1],
                        animation: animation,
                        posterWidth: colWidth,
                        posterHeight: posterHeight,
                        verticalGap: verticalGap,
                        scrollUp: false, // Opposite direction (Downward)
                      ),
                    ),
                    SizedBox(width: columnGap),
                    Expanded(
                      child: _AnimatedPosterColumn(
                        items: _kPosterWallColumns[2],
                        animation: animation,
                        posterWidth: colWidth,
                        posterHeight: posterHeight,
                        verticalGap: verticalGap,
                        scrollUp: true, // Opposite direction to Column 2 (Upward)
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Top subtle atmospheric vignette
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 76.h,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC170D20),
                      Color(0x00170D20),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom fade into the #170D20 canvas (matching Figma's bottom poster fade)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 150.h,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.58, 1.0],
                    colors: [
                      Color(0x00170D20),
                      Color(0xC8170D20),
                      Color(0xFF170D20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPosterColumn extends StatelessWidget {
  const _AnimatedPosterColumn({
    required this.items,
    required this.animation,
    required this.posterWidth,
    required this.posterHeight,
    required this.verticalGap,
    required this.scrollUp,
  });

  final List<MetaModel> items;
  final Animation<double> animation;
  final double posterWidth;
  final double posterHeight;
  final double verticalGap;
  final bool scrollUp;

  @override
  Widget build(BuildContext context) {
    final stride = posterHeight + verticalGap;
    final cycleHeight = items.length * stride;

    return AnimatedBuilder(
      animation: animation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var copy = 0; copy < 2; copy++)
            for (final meta in items)
              Padding(
                padding: EdgeInsets.only(bottom: verticalGap),
                child: _DecoratedWallPosterTile(
                  meta: meta,
                  width: posterWidth,
                  height: posterHeight,
                ),
              ),
        ],
      ),
      builder: (context, child) {
        final t = animation.value;
        // Seamless modular translation:
        // - scrollUp = true:  moves from 0 -> -cycleHeight
        // - scrollUp = false: moves from -cycleHeight -> 0 (downward)
        final dy = scrollUp ? -(t * cycleHeight) : ((t - 1.0) * cycleHeight);
        return OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: cycleHeight * 2,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: child,
          ),
        );
      },
    );
  }
}

class _DecoratedWallPosterTile extends StatelessWidget {
  const _DecoratedWallPosterTile({
    required this.meta,
    required this.width,
    required this.height,
  });

  final MetaModel meta;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDimens.posterRadius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppDimens.posterShadow,
        color: AppColors.surface2,
        border: Border.all(
          color: const Color(0x18FFFFFF),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: FallbackNetworkImage(
          urls: [meta.poster, meta.posterFallback],
          memWidth: width,
          memHeight: height,
          fallback: PosterFallback(meta: meta),
        ),
      ),
    );
  }
}
