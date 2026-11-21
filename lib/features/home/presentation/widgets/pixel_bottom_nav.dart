import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';

/// Figma "bottom navigation" (393×60): Home · Collections · My List · Search · profile avatar.
enum PixelTab { home, collections, myList, search, profile }

/// Active root tab selected across the app.
final activeTabProvider = StateProvider<PixelTab>((ref) => PixelTab.home);

const _activeHex = '#F6F6F3';
const _inactiveHex = '#9B9692';

const _avatarUrl =
    'https://api.builder.io/api/v1/image/assets/TEMP/573e496cc01f5a813d956b1b346ad877fc059d4a?width=1344';

const _wrap = 'xmlns="http://www.w3.org/2000/svg"';

String _homeSvg(String c) =>
    '<svg viewBox="0 0 23 23" fill="none" $_wrap><path d="M22.0996 8.92773V20.5791C22.0996 21.2473 21.934 21.5836 21.7588 21.7588C21.5836 21.934 21.2473 22.0996 20.5791 22.0996H2.4209C1.75271 22.0996 1.41639 21.934 1.24121 21.7588C1.06603 21.5836 0.900416 21.2473 0.900391 20.5791V8.92773L11.5 1.11816L22.0996 8.92773Z" stroke="$c" stroke-width="1.8" stroke-linecap="round"/></svg>';

String _collectionsSvg(String c) =>
    '<svg viewBox="0 0 23 23" fill="none" $_wrap><path d="M1.56113 7.45057C1.43875 6.99458 1.40741 6.51895 1.46892 6.05084C1.53042 5.58274 1.68356 5.13134 1.91958 4.72245C2.1556 4.31355 2.46988 3.95516 2.84446 3.66777C3.21903 3.38038 3.64657 3.16961 4.10263 3.04751L9.6557 1.5597C10.1118 1.43734 10.5875 1.40606 11.0557 1.46766C11.5239 1.52925 11.9753 1.68251 12.3842 1.91868C12.7931 2.15484 13.1515 2.46928 13.4388 2.84401C13.7262 3.21875 13.9368 3.64644 14.0588 4.10263L14.8839 7.18751H13.3975L12.6701 4.47351C12.5219 3.92133 12.1605 3.45063 11.6653 3.16489C11.1701 2.87915 10.5817 2.80176 10.0294 2.94976L4.47351 4.43757C3.92134 4.58579 3.45063 4.94723 3.16489 5.44243C2.87915 5.93762 2.80177 6.52602 2.94976 7.07826L4.43757 12.6328C4.58579 13.1849 4.94723 13.6556 5.44243 13.9414C5.93762 14.2271 6.52602 14.3045 7.07826 14.1565L7.18751 14.1278V15.6055C6.29669 15.7738 5.37518 15.5992 4.60768 15.1166C3.84018 14.6341 3.28341 13.8794 3.04895 13.0036L1.56113 7.45057ZM11.5 8.62501C10.7375 8.62501 10.0062 8.92791 9.46708 9.46708C8.92791 10.0062 8.62501 10.7375 8.62501 11.5V18.6875C8.62501 19.45 8.92791 20.1813 9.46708 20.7204C10.0062 21.2596 10.7375 21.5625 11.5 21.5625H18.6875C19.45 21.5625 20.1813 21.2596 20.7204 20.7204C21.2596 20.1813 21.5625 19.45 21.5625 18.6875V11.5C21.5625 10.7375 21.2596 10.0062 20.7204 9.46708C20.1813 8.92791 19.45 8.62501 18.6875 8.62501H11.5ZM10.0625 11.5C10.0625 11.1188 10.214 10.7531 10.4835 10.4835C10.7531 10.214 11.1188 10.0625 11.5 10.0625H18.6875C19.0688 10.0625 19.4344 10.214 19.704 10.4835C19.9736 10.7531 20.125 11.1188 20.125 11.5V18.6875C20.125 19.0688 19.9736 19.4344 19.704 19.704C19.4344 19.9736 19.0688 20.125 18.6875 20.125H11.5C11.1188 20.125 10.7531 19.9736 10.4835 19.704C10.214 19.4344 10.0625 19.0688 10.0625 18.6875V11.5ZM15.8125 12.2188C15.8125 12.0281 15.7368 11.8453 15.602 11.7105C15.4672 11.5757 15.2844 11.5 15.0938 11.5C14.9031 11.5 14.7203 11.5757 14.5855 11.7105C14.4507 11.8453 14.375 12.0281 14.375 12.2188V14.375H12.2188C12.0281 14.375 11.8453 14.4507 11.7105 14.5855C11.5757 14.7203 11.5 14.9031 11.5 15.0938C11.5 15.2844 11.5757 15.4672 11.7105 15.602C11.8453 15.7368 12.0281 15.8125 12.2188 15.8125H14.375V17.9688C14.375 18.1594 14.4507 18.3422 14.5855 18.477C14.7203 18.6118 14.9031 18.6875 15.0938 18.6875C15.2844 18.6875 15.4672 18.6118 15.602 18.477C15.7368 18.3422 15.8125 18.1594 15.8125 17.9688V15.8125H17.9688C18.1594 15.8125 18.3422 15.7368 18.477 15.602C18.6118 15.4672 18.6875 15.2844 18.6875 15.0938C18.6875 14.9031 18.6118 14.7203 18.477 14.5855C18.3422 14.4507 18.1594 14.375 17.9688 14.375H15.8125V12.2188Z" fill="$c"/></svg>';

String _myListSvg(String c) =>
    '<svg viewBox="0 0 23 23" fill="none" $_wrap><path d="M15.3333 3.83334H7.66667C6.6125 3.83334 5.75 4.69584 5.75 5.75001V18.2083C5.75 18.5533 5.93208 18.8696 6.22917 19.0421C6.52625 19.2146 6.89042 19.205 7.1875 19.0421L11.4904 16.4929L15.7933 19.0421C15.9467 19.1283 16.1096 19.1763 16.2821 19.1763C16.4546 19.1763 16.6079 19.1379 16.7612 19.0517C17.0583 18.8792 17.2404 18.5629 17.2404 18.2179V5.75959C17.2404 4.70543 16.3779 3.84293 15.3237 3.84293L15.3333 3.83334ZM15.3333 11.5V16.5313L11.9887 14.5475C11.8415 14.4578 11.6724 14.4103 11.5 14.4103C11.3276 14.4103 11.1585 14.4578 11.0112 14.5475L7.66667 16.5313V5.75001H15.3333V11.5Z" fill="$c"/></svg>';

String _searchSvg(String c) =>
    '<svg viewBox="0 0 23 23" fill="none" $_wrap><defs><clipPath id="c"><rect width="23" height="23" fill="white"/></clipPath></defs><g clip-path="url(#c)"><path d="M17 17L23 23" stroke="$c" stroke-width="1.9" stroke-linecap="round"/><circle cx="10" cy="10" r="9.05" stroke="$c" stroke-width="1.9"/></g></svg>';

/// Profile avatar: radius 7, image 672×1500 offset (-444, -1227) — straight from the export.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final s = Responsive.sw;
    return SizedBox(
      width: 23.r,
      height: 23.r,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7.r),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.avatarFallback)),
          Positioned(
            left: -444 * s,
            top: -1227 * s,
            width: 672 * s,
            height: 1500 * s,
            child: CachedNetworkImage(
              imageUrl: _avatarUrl,
              fit: BoxFit.fill,
              memCacheWidth: (672 * s).round(),
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 60px tall, 5px side padding, black. Selected tab = 74.6×54 pill (r15, 7% fill, 9% border).
class PixelBottomNav extends StatelessWidget {
  const PixelBottomNav({super.key, required this.current, required this.onChanged});
  final PixelTab current;
  final ValueChanged<PixelTab> onChanged;

  /// Labels are verbatim from the design export.
  static const _labels = {
    PixelTab.home: 'Home',
    PixelTab.collections: 'Collections',
    PixelTab.myList: 'My List',
    PixelTab.search: 'Search',
    PixelTab.profile: 'My OpenFlix',
  };

  static String labelOf(PixelTab t) => _labels[t]!;

  Widget _icon(PixelTab t, bool on) {
    final hex = on ? _activeHex : _inactiveHex;
    String? svg;
    switch (t) {
      case PixelTab.home:
        svg = _homeSvg(hex);
      case PixelTab.collections:
        svg = _collectionsSvg(hex);
      case PixelTab.myList:
        svg = _myListSvg(hex);
      case PixelTab.search:
        svg = _searchSvg(hex);
      case PixelTab.profile:
        return const _ProfileAvatar();
    }
    return SvgPicture.string(svg, width: 23.r, height: 23.r);
  }

  Widget _tab(PixelTab t) {
    final on = t == current;
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 23.r, height: 23.r, child: Center(child: _icon(t, on))),
      SizedBox(height: 4.h),
      Text(_labels[t]!, style: AppText.navLabel(on), maxLines: 1, softWrap: false),
    ]);

    void tap() {
      HapticFeedback.selectionClick();
      onChanged(t);
    }

    if (on) {
      return SizedBox(
        width: AppDimens.navPillWidth,
        height: AppDimens.navTabHeight,
        child: Material(
          color: AppColors.navPillFill,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.navPillRadius),
            side: const BorderSide(color: AppColors.navPillBorder),
          ),
          child: InkWell(
            onTap: tap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: content),
              ),
            ),
          ),
        ),
      );
    }
    return Expanded(
      child: SizedBox(
        height: AppDimens.navTabHeight,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: tap,
            child: Padding(
              padding: EdgeInsets.only(
                top: 7.h,
                bottom: 6.h,
                left: 2.w,
                right: 2.w,
              ),
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(5.w, 0, 5.w, bottom),
      child: SizedBox(
        height: AppDimens.navHeight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (final t in PixelTab.values) _tab(t),
        ]),
      ),
    );
  }
}
