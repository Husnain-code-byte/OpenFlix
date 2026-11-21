import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/utils/responsive.dart';
import '../../domain/models/playback_preferences.dart';
import '../controllers/playback_preferences_controller.dart';

/// Opens the sleek Primary + Fallback Watch Language picker modal.
Future<void> showLanguageSetupSheet(
  BuildContext context, {
  bool isFirstStartupPrompt = false,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB3000000),
      isDismissible: !isFirstStartupPrompt,
      enableDrag: !isFirstStartupPrompt,
      builder: (_) => LanguageSetupSheet(
        isFirstStartupPrompt: isFirstStartupPrompt,
      ),
    );

class LanguageSetupSheet extends ConsumerStatefulWidget {
  const LanguageSetupSheet({
    super.key,
    this.isFirstStartupPrompt = false,
  });

  final bool isFirstStartupPrompt;

  @override
  ConsumerState<LanguageSetupSheet> createState() => _LanguageSetupSheetState();
}

class _LanguageSetupSheetState extends ConsumerState<LanguageSetupSheet> {
  static const _kBg = Color(0xFF13161F);
  static const _kHandle = Color(0xFF363B47);
  static const _kCloseBg = Color(0xFF242A37);
  static const _kSurface = Color(0xFF191D29);
  static const _kHairline = Color(0x14FFFFFF);

  late String _primary;
  late String _fallback;
  bool _editingFallback = false;
  String _searchQuery = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(playbackPreferencesControllerProvider).valueOrNull ??
        const PlaybackPreferences();
    _primary = prefs.primaryLanguage;
    _fallback = prefs.fallbackLanguage;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await ref.read(playbackPreferencesControllerProvider.notifier).setLanguages(
          primary: _primary,
          fallback: _fallback,
          markSetupComplete: true,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final screenH = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final selectedCode = _editingFallback ? _fallback : _primary;

    final filtered = kSupportedWatchLanguages.where((lang) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return lang.name.toLowerCase().contains(q) ||
          lang.nativeName.toLowerCase().contains(q) ||
          lang.code.toLowerCase().contains(q) ||
          lang.iso3.toLowerCase().contains(q);
    }).toList(growable: false);

    final primaryOpt = languageOptionForCode(_primary);
    final fallbackOpt = languageOptionForCode(_fallback);

    return PopScope(
      canPop: !widget.isFirstStartupPrompt,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenH * 0.84),
          decoration: BoxDecoration(
            color: _kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            border: const Border(
              top: BorderSide(color: Color(0x14FFFFFF)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 12.h),
                Center(
                  child: Container(
                    width: 44.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: _kHandle,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                Padding(
                  padding: EdgeInsets.fromLTRB(22.w, 0, 22.w, 12.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Watch Languages',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 19.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.45,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              'Auto-picks streams, audio tracks & smart subtitles',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.sp,
                                color: const Color(0xFFA1A1AA),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!widget.isFirstStartupPrompt)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 32.r,
                            height: 32.r,
                            decoration: const BoxDecoration(
                              color: _kCloseBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16.r,
                              color: const Color(0xFFD4D4D4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Two-slot segmented switcher: Primary vs Fallback
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22.w),
                  child: Row(
                    children: [
                      Expanded(
                        child: _LanguageSlotCard(
                          eyebrow: 'PRIMARY',
                          language: primaryOpt,
                          selected: !_editingFallback,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _editingFallback = false);
                          },
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: _LanguageSlotCard(
                          eyebrow: 'FALLBACK',
                          language: fallbackOpt,
                          selected: _editingFallback,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _editingFallback = true);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 12.h),

                // Compact search input
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22.w),
                  child: Container(
                    height: 40.h,
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0D14),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: _kHairline),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 17.r,
                          color: const Color(0xFF71717A),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: GoogleFonts.inter(
                              fontSize: 13.sp,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: _editingFallback
                                  ? 'Pick fallback if ${primaryOpt.name} is unavailable...'
                                  : 'Pick your primary watch language...',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 12.5.sp,
                                color: const Color(0xFF71717A),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 10.h),
                const Divider(height: 1, color: _kHairline),

                // Language rows
                Flexible(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => SizedBox(height: 4.h),
                    itemBuilder: (context, idx) {
                      final opt = filtered[idx];
                      final isSelected = opt.code == selectedCode;
                      final isOtherSlot = (!_editingFallback &&
                              opt.code == _fallback) ||
                          (_editingFallback && opt.code == _primary);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10.r),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_editingFallback) {
                              _fallback = opt.code;
                            } else {
                              _primary = opt.code;
                              if (_fallback == opt.code) {
                                _fallback = opt.code == 'en' ? 'hi' : 'en';
                              }
                              _editingFallback = true;
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 11.h,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0x14FFFFFF)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0x2EFFFFFF)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                opt.flagEmoji,
                                style: TextStyle(fontSize: 18.sp),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Text(
                                  opt.name == opt.nativeName
                                      ? opt.name
                                      : '${opt.name} · ${opt.nativeName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 14.5.sp,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (isOtherSlot && !isSelected)
                                Container(
                                  margin: EdgeInsets.only(right: 8.w),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 7.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kSurface,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: _kHairline),
                                  ),
                                  child: Text(
                                    _editingFallback ? 'Primary' : 'Fallback',
                                    style: GoogleFonts.inter(
                                      fontSize: 10.sp,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFA1A1AA),
                                    ),
                                  ),
                                ),
                              if (isSelected)
                                Icon(
                                  Icons.check_rounded,
                                  size: 20.r,
                                  color: Colors.white,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Padding(
                  padding: EdgeInsets.fromLTRB(
                    22.w,
                    8.h,
                    22.w,
                    14.h + (safeBottom > 0 ? 4.h : 0),
                  ),
                  child: SizedBox(
                    height: 46.h,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 18.r,
                              height: 18.r,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              'Save (${primaryOpt.name} → ${fallbackOpt.name})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSlotCard extends StatelessWidget {
  const _LanguageSlotCard({
    required this.eyebrow,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final String eyebrow;
  final WatchLanguageOption language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E2433) : const Color(0xFF191D29),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: selected
                ? const Color(0x66FFFFFF)
                : const Color(0x14FFFFFF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: selected
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFF8B92A5),
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              children: [
                Text(
                  language.flagEmoji,
                  style: TextStyle(fontSize: 14.sp),
                ),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    language.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
