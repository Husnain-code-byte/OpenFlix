import 'package:flutter/material.dart';

import '../utils/responsive.dart';

/// Tokens extracted from the Figma frames: Home (1:9), App icon (32:15),
/// bottom navigation (10:29), Netflix top navigation (20:422), Featured film (20:73).
class AppColors {
  AppColors._();
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF0B0D10);
  static const surface2 = Color(0xFF14171C);
  static const rowHeading = Color(0xFF8B8B8B);
  static const textPrimary = Color(0xFFF6F6F3);
  static const textMuted = Color(0xFF9B9692);
  static const accent = Color(0xFF0779FF);

  // rgba(255,255,255,.07) fill / rgba(255,255,255,.09) border — nav pill and chips
  static const navPillFill = Color(0x12FFFFFF);
  static const navPillBorder = Color(0x17FFFFFF);
  // Pressed/selected chip affordance (not in the design; default look is the spec above)
  static const chipActiveFill = Color(0x2EFFFFFF);
  static const chipActiveBorder = Color(0x4DFFFFFF);

  // Featured film
  static const heroBg = Color(0xFF071215);
  static const heroBorder = Color(0x21FFFFFF); // rgba(255,255,255,.13)
  static const heroTitle = Color(0xFFE5F5F3);
  static const heroRule = Color(0xFF9DB8B6);
  static const heroConnector = Color(0xFFB8D2D0);
  static const heroMeta = Color(0xFFA9B5B6);
  static const onLight = Color(0xFF090D0E);
  static const heroSecondaryBtn = Color(0x26FFFFFF); // rgba(255,255,255,.15)
  static const avatarFallback = Color(0xFF2A2F36);

  // Collections cards (Figma frame 151:21)
  static const collectionCardOuterBg = Color(0xFF171717);
  static const collectionCardInnerBg = Color(0xFF262626);
  static const collectionCardBorder = Color(0xFF262626);

  // App icon
  static const iconTop = Color(0xFF162638);
  static const iconMid = Color(0xFF08121F);
  static const iconBottom = Color(0xFF04080F);

  static const iconGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [iconTop, iconMid, iconBottom],
  );

  /// "Title and controls scrim" — verbatim from the export.
  static const heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.fromRGBO(0, 20, 25, 0.06),
      Color.fromRGBO(0, 20, 25, 0.0),
      Color.fromRGBO(3, 16, 20, 0.36),
      Color.fromRGBO(6, 18, 22, 0.86),
      Color(0xFF071215),
    ],
    stops: [0.0, 0.42, 0.62, 0.79, 1.0],
  );
}

class AppDimens {
  AppDimens._();
  // Responsive portrait cards shared by home and related rows (113×170 on reference 423.53×948.24 dp).
  static double get posterWidth => 113.w;
  static double get posterHeight => 170.w;
  static double get posterRadius => 7.r;
  static double get posterGap => 8.w;
  static double get posterStride => posterWidth + posterGap;
  static double get screenPadding => 8.w;
  static double get rowGap => 10.h;
  static double get rowSpacing => 12.h;

  // Navigation
  static double get topNavHeight => 8.h + 14.h + headerH + headerGap + rowH;
  static double get navHeight => 60.h;
  static double get navTabHeight => 54.h;
  static double get navPillRadius => 15.r;
  static double get navPillWidth => 74.6.w;

  // Top-nav inner geometry, relative to the padded area under the status bar.
  // From Figma frame 20:422: padding 8 top / 14 bottom, gap 12, header 44, chip row 46.
  static double get headerH => 44.h; // "Home header" height
  static double get headerGap => 12.h; // gap between header and chip row
  static double get rowTop => headerH + headerGap; // headerH + headerGap
  static double get rowH => 46.h; // "Browse categories" height
  static double get titleLeft => 13.w; // header padding-left
  static double get rowLeft => 12.w; // chip row padding-left
  static double get chipGap => 6.w; // gap between chips
  static double get titleFontSize => 28.sp; // "Home" Arimo 28 bold
  static double get chipFontSize => 16.sp; // chip label

  // Featured film
  static double get heroTopPad => 6.h;
  static double get heroMinHeight => 540.h;
  static double get heroMaxHeight => 720.h;
  static double get heroGutter => 18.w;
  static double get heroRadius => 10.r;
  static double get afterHeroGap => 26.h;

  // Collections screen (Figma frame 151:21)
  static double get collectionsScreenPadding => 11.w; // left: 11px
  static double get collectionsHeroTopGap => 8.h; // top gap after MainHeader
  static double get collectionsHeroHeight => 189.w; // 371×189 highlight card
  static double get collectionsHeroRadius => 10.r; // border-radius: 10px
  static double get afterCollectionsHeroGap => 17.h; // gap after highlight card
  static double get collectionCardWidth => 192.w; // landscape card width: 192px
  static double get collectionCardHeight => 112.w; // landscape card height: 112px
  static double get collectionCardRadius => 8.r; // border-radius: 8px
  static double get collectionCardStride => collectionCardWidth + posterGap;
  static double get collectionsRowSpacing => 16.h;

  /// Hero height fills the screen between the top nav and the bottom nav,
  /// clamped so it never gets smaller than the scaled Figma frame.
  static double heroSlideHeight(BuildContext context) {
    Responsive.init(context);
    final mq = MediaQuery.of(context);
    final available = mq.size.height - topNavHeight - navHeight - mq.padding.top - mq.padding.bottom;
    return (available * 0.8).clamp(heroMinHeight, heroMaxHeight).toDouble();
  }

  static double heroCardHeight(BuildContext context) => heroSlideHeight(context) - heroTopPad;

  static const posterShadow = [
    BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

/// Fallback system font families optimized for low-end startup and perfect layout.
const _systemFallbacks = ['Roboto', 'San Francisco', 'sans-serif'];

class AppText {
  AppText._();

  static const TextStyle _base = TextStyle(
    fontFamilyFallback: _systemFallbacks,
    decoration: TextDecoration.none,
  );

  static TextStyle get rowHeading => _base.copyWith(
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
        color: AppColors.rowHeading,
      );

  /// Tab label: Arimo 10.5 / line-height 12, bold when selected.
  static TextStyle navLabel(bool active) => _base.copyWith(
        fontSize: 10.5.sp,
        height: 12 / 10.5,
        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
        color: active ? AppColors.textPrimary : AppColors.textMuted,
      );

  static TextStyle get pageTitle => _base.copyWith(
        fontSize: 28.sp,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get chip => _base.copyWith(
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle heroButton(Color c) => _base.copyWith(
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        color: c,
      );

  static TextStyle get heroGenre => _base.copyWith(
        fontSize: 12.sp,
        height: 15 / 12,
        color: AppColors.textPrimary,
      );

  static TextStyle get heroMeta => _base.copyWith(
        fontSize: 11.sp,
        height: 14 / 11,
        color: AppColors.heroMeta,
      );

  /// Syncopate wordmark line (lead 34/37, finish 23/28, connector 8/10).
  static TextStyle syncopate(double size, double lineHeight, Color c) => _base.copyWith(
        fontFamily: 'Syncopate',
        fontSize: size.sp,
        height: lineHeight / size,
        fontWeight: FontWeight.w700,
        color: c,
      );

  static TextStyle get brand => _base.copyWith(
        fontSize: 34.sp,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.05,
      );

  /// Details screen play button: Inter 16 / 24, weight 700, #000 (Figma 26:387)
  static TextStyle get detailsButton => _base.copyWith(
        fontSize: 16.sp,
        height: 24 / 16,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      );
}

class AppTheme {
  AppTheme._();
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.accent,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
        fontFamilyFallback: _systemFallbacks,
      ),
      splashFactory: InkSparkle.splashFactory,
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    );
  }
}
