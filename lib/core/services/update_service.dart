import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_links.dart';
import '../utils/responsive.dart';

/// Parsed metadata for a GitHub release returned by [AppLinks.releasesApiUrl].
class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.rawTagName,
    required this.cleanVersion,
    required this.installedVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  /// Original tag string from GitHub (e.g., `v1.0.1`).
  final String rawTagName;

  /// Normalized semantic version string without leading `v` (e.g., `1.0.1`).
  final String cleanVersion;

  /// Currently installed app version (e.g., `0.1.0`).
  final String installedVersion;

  /// Display title of the release.
  final String releaseTitle;

  /// Markdown / plain-text release notes (`body`).
  final String releaseNotes;

  /// Best matching `.apk` asset `browser_download_url` or release `html_url`.
  final String downloadUrl;

  String get displayTag =>
      rawTagName.startsWith('v') || rawTagName.startsWith('V')
          ? rawTagName
          : 'v$cleanVersion';
}

enum UpdateCheckStatus {
  updateAvailable,
  upToDate,
  error,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.installedVersion,
    this.updateInfo,
  });

  final UpdateCheckStatus status;
  final String installedVersion;
  final ReleaseUpdateInfo? updateInfo;
}

/// Lightweight GitHub Releases auto-updater and external link launcher.
class UpdateService {
  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                headers: const {
                  'Accept': 'application/vnd.github+json',
                  'X-GitHub-Api-Version': '2022-11-28',
                  'User-Agent': 'OpenFlix-App',
                },
              ),
            );

  static final UpdateService instance = UpdateService();

  static const String _kDismissedVersionPrefKey =
      'openflix_dismissed_update_tag_v1';

  final Dio _dio;
  bool _silentStartupCheckRan = false;
  static String? _cachedInstalledVersion;

  /// Reads the installed app version dynamically via `package_info_plus`.
  Future<String> getInstalledVersion() async {
    if (_cachedInstalledVersion != null &&
        _cachedInstalledVersion!.isNotEmpty) {
      return _cachedInstalledVersion!;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        _cachedInstalledVersion = version;
        return version;
      }
    } catch (_) {}
    return '1.0.0';
  }

  /// Strips leading `v`/`V`, pre-release labels, and build metadata.
  static String normalizeVersion(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    final plusIdx = s.indexOf('+');
    if (plusIdx != -1) {
      s = s.substring(0, plusIdx);
    }
    final dashIdx = s.indexOf('-');
    if (dashIdx != -1) {
      s = s.substring(0, dashIdx);
    }
    return s.trim();
  }

  /// Compares [remoteRaw] against [installedRaw] semantically (`major.minor.patch`).
  /// Returns `true` strictly when `remote > installed`.
  static bool isNewerVersion(String remoteRaw, String installedRaw) {
    final remoteParts = _parseSemverParts(remoteRaw);
    final localParts = _parseSemverParts(installedRaw);
    if (remoteParts == null || localParts == null) return false;

    for (var i = 0; i < 3; i++) {
      if (remoteParts[i] > localParts[i]) return true;
      if (remoteParts[i] < localParts[i]) return false;
    }
    return false;
  }

  static List<int>? _parseSemverParts(String raw) {
    final cleaned = normalizeVersion(raw);
    if (cleaned.isEmpty) return null;
    final tokens = cleaned.split('.');
    final nums = <int>[];
    for (var i = 0; i < 3; i++) {
      if (i >= tokens.length) {
        nums.add(0);
      } else {
        final match = RegExp(r'\d+').firstMatch(tokens[i]);
        if (match == null) return null;
        nums.add(int.tryParse(match.group(0)!) ?? 0);
      }
    }
    return nums;
  }

  /// Selects the best `.apk` asset `browser_download_url` for the current device ABI,
  /// falling back to a universal `.apk`, or finally `html_url`.
  static String selectBestDownloadUrl(
    List<dynamic> assets, {
    required String fallbackHtmlUrl,
  }) {
    final apkAssets = <({String name, String url})>[];
    for (final item in assets) {
      if (item is! Map) continue;
      final name = (item['name']?.toString() ?? '').trim();
      final url = (item['browser_download_url']?.toString() ?? '').trim();
      if (url.isEmpty) continue;
      if (name.toLowerCase().endsWith('.apk') ||
          url.toLowerCase().endsWith('.apk')) {
        apkAssets.add((name: name.toLowerCase(), url: url));
      }
    }

    if (apkAssets.isEmpty) {
      return fallbackHtmlUrl.isNotEmpty
          ? fallbackHtmlUrl
          : AppLinks.releasesHtmlFallbackUrl;
    }

    final preferredAbiTokens = _preferredAbiTokens();
    for (final token in preferredAbiTokens) {
      for (final asset in apkAssets) {
        if (asset.name.contains(token) ||
            asset.url.toLowerCase().contains(token)) {
          return asset.url;
        }
      }
    }

    // Fallback to universal APK (no foreign ABI tag in name).
    const knownAbiTags = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
    for (final asset in apkAssets) {
      final hasSpecificAbi = knownAbiTags.any(asset.name.contains);
      if (!hasSpecificAbi) {
        return asset.url;
      }
    }

    // Fallback to first available APK asset.
    return apkAssets.first.url;
  }

  static List<String> _preferredAbiTokens() {
    try {
      final abi = Abi.current();
      if (abi == Abi.androidArm64 || abi == Abi.linuxArm64) {
        return const ['arm64-v8a', 'arm64'];
      }
      if (abi == Abi.androidArm || abi == Abi.linuxArm) {
        return const ['armeabi-v7a', 'armeabi', 'arm32'];
      }
      if (abi == Abi.androidX64 || abi == Abi.linuxX64) {
        return const ['x86_64'];
      }
      if (abi == Abi.androidIA32 || abi == Abi.linuxIA32) {
        return const ['x86'];
      }
    } catch (_) {}

    final ver = Platform.version.toLowerCase();
    if (ver.contains('arm64') || ver.contains('aarch64')) {
      return const ['arm64-v8a', 'arm64'];
    }
    if (ver.contains('arm')) {
      return const ['armeabi-v7a', 'armeabi'];
    }
    return const ['arm64-v8a', 'armeabi-v7a'];
  }

  /// Queries [AppLinks.releasesApiUrl] and compares against [getInstalledVersion].
  Future<UpdateCheckResult> checkForUpdate() async {
    final installedVersion = await getInstalledVersion();
    try {
      final response = await _dio
          .get<dynamic>(
            AppLinks.releasesApiUrl,
            options: Options(
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {
                'Accept': 'application/vnd.github+json',
              },
            ),
          )
          .timeout(const Duration(seconds: 10));

      final data = response.data;
      if (response.statusCode != 200 || data is! Map) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          installedVersion: installedVersion,
        );
      }

      final rawTag = (data['tag_name']?.toString() ?? '').trim();
      final cleanRemote = normalizeVersion(rawTag);
      if (cleanRemote.isEmpty) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          installedVersion: installedVersion,
        );
      }

      if (!isNewerVersion(cleanRemote, installedVersion)) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          installedVersion: installedVersion,
        );
      }

      final assets =
          data['assets'] is List ? (data['assets'] as List<dynamic>) : const [];
      final htmlUrl =
          (data['html_url']?.toString() ?? AppLinks.releasesHtmlFallbackUrl)
              .trim();
      final downloadUrl = selectBestDownloadUrl(
        assets,
        fallbackHtmlUrl: htmlUrl,
      );
      final title = (data['name']?.toString() ?? '').trim();
      final body = (data['body']?.toString() ?? '').trim();

      return UpdateCheckResult(
        status: UpdateCheckStatus.updateAvailable,
        installedVersion: installedVersion,
        updateInfo: ReleaseUpdateInfo(
          rawTagName: rawTag,
          cleanVersion: cleanRemote,
          installedVersion: installedVersion,
          releaseTitle: title.isNotEmpty ? title : 'OpenFlix $rawTag',
          releaseNotes: body.isNotEmpty
              ? body
              : 'Bug fixes, performance improvements, and UI refinements.',
          downloadUrl: downloadUrl,
        ),
      );
    } catch (_) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        installedVersion: installedVersion,
      );
    }
  }

  /// Persists the dismissed release tag when the user taps "Later".
  Future<void> dismissVersionTag(String rawTagOrCleanVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kDismissedVersionPrefKey,
        normalizeVersion(rawTagOrCleanVersion),
      );
    } catch (_) {}
  }

  /// Checks if the user previously tapped "Later" for [rawTagOrCleanVersion].
  Future<bool> isVersionDismissed(String rawTagOrCleanVersion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissed = prefs.getString(_kDismissedVersionPrefKey);
      if (dismissed == null || dismissed.isEmpty) return false;
      return normalizeVersion(dismissed) ==
          normalizeVersion(rawTagOrCleanVersion);
    } catch (_) {
      return false;
    }
  }

  /// Runs once per app session after the home screen settles.
  /// Never blocks startup or shows error popups on offline/404/rate-limit failures.
  Future<void> runSilentStartupCheck(BuildContext context) async {
    if (_silentStartupCheckRan) return;
    _silentStartupCheckRan = true;

    try {
      final result = await checkForUpdate();
      if (result.status != UpdateCheckStatus.updateAvailable ||
          result.updateInfo == null) {
        return;
      }
      final info = result.updateInfo!;
      final dismissed = await isVersionDismissed(info.cleanVersion);
      if (dismissed || !context.mounted) return;

      await showUpdateBottomSheet(context, info: info);
    } catch (_) {
      // Silent by design on startup.
    }
  }

  /// Opens an external URL in the system browser / Discord app via `url_launcher`.
  static Future<bool> launchExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return false;
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

const String _kUpdateSheetCloseSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M4 12L12 4M4 4L12 12" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" stroke="#D4D4D4"/>'
    '</svg>';

/// Slides up the OLED-black / dark-surface modal bottom sheet matching the
/// `Select season` sheet style when a newer version of OpenFlix is available.
Future<void> showUpdateBottomSheet(
  BuildContext context, {
  required ReleaseUpdateInfo info,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (sheetContext) => OpenFlixUpdateSheet(info: info),
  );
}

class OpenFlixUpdateSheet extends StatelessWidget {
  const OpenFlixUpdateSheet({
    super.key,
    required this.info,
  });

  final ReleaseUpdateInfo info;

  Future<void> _onLater(BuildContext context) async {
    HapticFeedback.selectionClick();
    await UpdateService.instance.dismissVersionTag(info.cleanVersion);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onUpdateNow(BuildContext context) async {
    HapticFeedback.lightImpact();
    await UpdateService.launchExternalUrl(info.downloadUrl);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.76;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Container(
        decoration: ShapeDecoration(
          color: const Color(0xFF000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            side: const BorderSide(color: Color(0x14FFFFFF), width: 1),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(0, -10),
              blurRadius: 35,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Center Drag Handle (matches Select season sheet)
                Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Center(
                    child: Container(
                      width: 44.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: const Color(0xFF363B47),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),

                // Sheet Header (Title + Version Badge + 32x32 Close Button)
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 14.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Update Available',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 20.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: 30 / 20,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 9.w,
                                    vertical: 3.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x1A4ADE80),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0x334ADE80),
                                    ),
                                  ),
                                  child: Text(
                                    info.displayTag,
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5.sp,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF4ADE80),
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              'Installed v${info.installedVersion} → ${info.displayTag}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF8491A5),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Material(
                        color: const Color(0xFF242A37),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _onLater(context),
                          child: SizedBox(
                            width: 32.r,
                            height: 32.r,
                            child: Center(
                              child: SvgPicture.string(
                                _kUpdateSheetCloseSvg,
                                width: 16.r,
                                height: 16.r,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Scrollable Release Notes Surface (#141414 card with hairline border)
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16.r),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: const Color(0x14FFFFFF)),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "WHAT'S NEW",
                              style: GoogleFonts.inter(
                                fontSize: 10.5.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF8491A5),
                                letterSpacing: 0.7,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              info.releaseNotes,
                              style: GoogleFonts.inter(
                                fontSize: 13.5.sp,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFFE4E4E7),
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Action Buttons: "Later" & Primary "Update Now"
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24.w,
                    16.h,
                    24.w,
                    20.h + bottomInset,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(12.r),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _onLater(context),
                            child: Container(
                              height: 46.h,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: const Color(0x1FFFFFFF),
                                ),
                              ),
                              child: Text(
                                'Later',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFE4E4E7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        flex: 2,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12.r),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _onUpdateNow(context),
                            child: Container(
                              height: 46.h,
                              padding: EdgeInsets.symmetric(horizontal: 16.w),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.system_update_alt_rounded,
                                    size: 17.r,
                                    color: Colors.black,
                                  ),
                                  SizedBox(width: 8.w),
                                  Flexible(
                                    child: Text(
                                      'Update Now',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 14.sp,
                                        fontWeight: FontWeight.w700,
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
                    ],
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
