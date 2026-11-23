import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io' show Directory, File, Platform;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_links.dart';
import '../errors/user_error.dart';
import '../utils/responsive.dart';

/// Parsed entry from GitHub Release markdown notes.
class ReleaseNoteEntry {
  const ReleaseNoteEntry({
    required this.text,
    this.isHeading = false,
  });

  final String text;
  final bool isHeading;
}

/// Selected APK asset matched for the current device ABI.
class SelectedApkAsset {
  const SelectedApkAsset({
    required this.name,
    required this.url,
    this.sizeBytes,
  });

  final String name;
  final String url;
  final int? sizeBytes;
}

/// Parsed metadata for a GitHub release returned by [AppLinks.releasesApiUrl].
class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.rawTagName,
    required this.cleanVersion,
    required this.installedVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.downloadUrl,
    this.assetName,
    this.assetSizeBytes,
  });

  /// Original tag string from GitHub (e.g., `v1.0.1`).
  final String rawTagName;

  /// Normalized semantic version string without leading `v` (e.g., `1.0.1`).
  final String cleanVersion;

  /// Currently installed app version (e.g., `1.1.1`).
  final String installedVersion;

  /// Display title of the release.
  final String releaseTitle;

  /// Raw markdown / plain-text release notes (`body`).
  final String releaseNotes;

  /// Direct `.apk` asset `browser_download_url`.
  final String downloadUrl;

  /// Matched APK filename (e.g., `OpenFlix-arm64-v8a.apk`).
  final String? assetName;

  /// Asset size in bytes when provided by GitHub Releases.
  final int? assetSizeBytes;

  String get displayTag =>
      rawTagName.startsWith('v') || rawTagName.startsWith('V')
          ? rawTagName
          : 'v$cleanVersion';

  String get installedDisplayTag {
    final norm = UpdateService.normalizeVersion(installedVersion);
    return norm.isEmpty ? installedVersion : 'v$norm';
  }

  String? get formattedSizeMb {
    final bytes = assetSizeBytes;
    if (bytes == null || bytes <= 0) return null;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<ReleaseNoteEntry> get parsedNotes =>
      UpdateService.parseReleaseNotes(releaseNotes);
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

/// Lightweight GitHub Releases auto-updater with ABI selection, in-app APK
/// download + Android package installer trigger, and per-session deduplication.
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
  static const _launcherChannel = MethodChannel('openflix/launcher');

  final Dio _dio;
  bool _silentStartupCheckRan = false;
  bool _dialogCurrentlyOpen = false;
  final Set<String> _dismissedSessionVersions = <String>{};
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
    return '1.1.1';
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

  /// Selects the best matching `.apk` asset for the current device ABI
  /// (`arm64-v8a` -> `universal` -> first APK). Returns `null` when the
  /// release contains no valid `.apk` assets.
  static SelectedApkAsset? selectBestApkAsset(
    List<dynamic> assets, {
    List<String>? preferredAbiTokensOverride,
  }) {
    final apkAssets = <SelectedApkAsset>[];
    for (final item in assets) {
      if (item is! Map) continue;
      final name = (item['name']?.toString() ?? '').trim();
      final url = (item['browser_download_url']?.toString() ?? '').trim();
      final sizeRaw = item['size'];
      final sizeBytes = sizeRaw is num ? sizeRaw.toInt() : null;
      if (url.isEmpty) continue;
      final lowerName = name.toLowerCase();
      final lowerUrl = url.toLowerCase();
      if (lowerName.endsWith('.apk') || lowerUrl.endsWith('.apk')) {
        apkAssets.add(
          SelectedApkAsset(
            name: name,
            url: url,
            sizeBytes: sizeBytes,
          ),
        );
      }
    }

    if (apkAssets.isEmpty) return null;

    final preferredAbiTokens =
        preferredAbiTokensOverride ?? _preferredAbiTokens();
    for (final token in preferredAbiTokens) {
      for (final asset in apkAssets) {
        if (asset.name.toLowerCase().contains(token) ||
            asset.url.toLowerCase().contains(token)) {
          return asset;
        }
      }
    }

    // Prefer explicitly tagged universal APK or APK without a foreign ABI tag.
    for (final asset in apkAssets) {
      if (asset.name.toLowerCase().contains('universal')) {
        return asset;
      }
    }
    const knownAbiTags = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
    for (final asset in apkAssets) {
      final hasSpecificAbi =
          knownAbiTags.any((t) => asset.name.toLowerCase().contains(t));
      if (!hasSpecificAbi) {
        return asset;
      }
    }

    return apkAssets.first;
  }

  /// Backward-compatible helper returning the best APK URL or fallback HTML URL.
  static String selectBestDownloadUrl(
    List<dynamic> assets, {
    required String fallbackHtmlUrl,
  }) {
    final asset = selectBestApkAsset(assets);
    if (asset != null) return asset.url;
    return fallbackHtmlUrl.isNotEmpty
        ? fallbackHtmlUrl
        : AppLinks.releasesHtmlFallbackUrl;
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

  /// Parses GitHub Release markdown `body` into clean, readable heading and
  /// bullet rows (stripping raw `#`, `**`, `__`, backticks, links, and empty lines).
  static List<ReleaseNoteEntry> parseReleaseNotes(String rawBody) {
    final normalized = rawBody.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const [
        ReleaseNoteEntry(
          text: 'Bug fixes, playback improvements, and UI refinements.',
        ),
      ];
    }

    final entries = <ReleaseNoteEntry>[];
    for (final rawLine in normalized.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('<!--') ||
          line.startsWith('---') ||
          line.startsWith('***') ||
          line.startsWith('|') ||
          line.startsWith('![')) {
        continue;
      }
      if (line.toLowerCase().startsWith('**full changelog') ||
          line.toLowerCase().startsWith('full changelog')) {
        continue;
      }

      final headingMatch = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final cleaned = _cleanMarkdownInline(headingMatch.group(1)!);
        if (cleaned.isNotEmpty) {
          entries.add(ReleaseNoteEntry(text: cleaned, isHeading: true));
        }
        continue;
      }

      final bulletMatch =
          RegExp(r'^(?:[-*•+]|\d+[.)])\s+(.+)$').firstMatch(line);
      if (bulletMatch != null) {
        final cleaned = _cleanMarkdownInline(bulletMatch.group(1)!);
        if (cleaned.isNotEmpty) {
          entries.add(ReleaseNoteEntry(text: cleaned));
        }
        continue;
      }

      final cleaned = _cleanMarkdownInline(line);
      if (cleaned.isNotEmpty) {
        entries.add(ReleaseNoteEntry(text: cleaned));
      }
    }

    if (entries.isEmpty) {
      return const [
        ReleaseNoteEntry(
          text: 'Bug fixes, playback improvements, and UI refinements.',
        ),
      ];
    }
    return entries;
  }

  static String _cleanMarkdownInline(String input) {
    var s = input.trim();
    // Convert markdown links [label](url) -> label
    s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );
    // Strip bold/italic/code markers
    s = s.replaceAll('**', '');
    s = s.replaceAll('__', '');
    s = s.replaceAll('`', '');
    s = s.replaceAll(RegExp(r'^#+\s*'), '');
    // Collapse excess whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Queries [AppLinks.releasesApiUrl] and compares against [getInstalledVersion].
  /// Only reports [UpdateCheckStatus.updateAvailable] when `remote > installed`
  /// AND at least one valid `.apk` asset exists on the release.
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
      final bestApk = selectBestApkAsset(assets);
      if (bestApk == null) {
        // Ignore releases without valid APK assets so users are never prompted
        // for source-only tags or in-progress CI releases.
        return UpdateCheckResult(
          status: UpdateCheckStatus.upToDate,
          installedVersion: installedVersion,
        );
      }

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
          downloadUrl: bestApk.url,
          assetName: bestApk.name,
          assetSizeBytes: bestApk.sizeBytes,
        ),
      );
    } catch (e) {
      debugPrint('[UpdateService] Silent check failed: $e');
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        installedVersion: installedVersion,
      );
    }
  }

  /// Marks [rawTagOrCleanVersion] dismissed for the remainder of this app session.
  void dismissForCurrentSession(String rawTagOrCleanVersion) {
    final norm = normalizeVersion(rawTagOrCleanVersion);
    if (norm.isNotEmpty) {
      _dismissedSessionVersions.add(norm);
    }
  }

  bool isDismissedInSession(String rawTagOrCleanVersion) {
    final norm = normalizeVersion(rawTagOrCleanVersion);
    return norm.isNotEmpty && _dismissedSessionVersions.contains(norm);
  }

  /// Runs once per app session shortly after startup.
  /// Never blocks startup or shows error popups when offline/rate-limited.
  Future<void> runSilentStartupCheck(BuildContext context) async {
    if (_silentStartupCheckRan || _dialogCurrentlyOpen) return;
    _silentStartupCheckRan = true;

    try {
      final result = await checkForUpdate();
      if (result.status != UpdateCheckStatus.updateAvailable ||
          result.updateInfo == null) {
        return;
      }
      final info = result.updateInfo!;
      if (isDismissedInSession(info.cleanVersion) || !context.mounted) return;

      await showUpdateDialog(context, info: info);
    } catch (e) {
      // Silent by design on startup.
      debugPrint('[UpdateService] Startup check ignored: $e');
    }
  }

  /// Downloads the matching ABI APK into Android's cache directory and triggers
  /// the native Android package installer via `FileProvider`. Falls back to
  /// external browser download if native install is unavailable.
  Future<bool> downloadAndInstallApk(
    ReleaseUpdateInfo info, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!Platform.isAndroid) {
      return launchExternalUrl(info.downloadUrl);
    }

    String? cacheDir;
    try {
      cacheDir = await _launcherChannel.invokeMethod<String>('getCacheDir');
    } catch (_) {}
    final baseDirPath =
        (cacheDir != null && cacheDir.isNotEmpty) ? cacheDir : Directory.systemTemp.path;

    final safeVer = info.cleanVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final apkFile = File('$baseDirPath/openflix_update_$safeVer.apk');
    if (await apkFile.exists()) {
      try {
        await apkFile.delete();
      } catch (_) {}
    }

    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 8,
        headers: const {'User-Agent': 'OpenFlix-App'},
      ),
    );

    await downloadDio.download(
      info.downloadUrl,
      apkFile.path,
      cancelToken: cancelToken,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        final effectiveTotal = total > 0 ? total : (info.assetSizeBytes ?? -1);
        onProgress(received, effectiveTotal);
      },
    );

    if (cancelToken?.isCancelled == true) return false;

    try {
      final launched = await _launcherChannel.invokeMethod<bool>(
        'installApk',
        {'path': apkFile.path},
      );
      if (launched == true) return true;
    } catch (e) {
      debugPrint('[UpdateService] Native installApk failed: $e');
    }

    // Fallback to browser if native package installer could not open.
    return launchExternalUrl(info.downloadUrl);
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

/// Shows the minimal OLED-black "Update Available" modal card (`#09090B`
/// surface, `1px #27272A` hairline border, `20px` radius, dimmed `#000000`
/// backdrop).
Future<void> showUpdateDialog(
  BuildContext context, {
  required ReleaseUpdateInfo info,
}) async {
  if (UpdateService.instance._dialogCurrentlyOpen) return;
  UpdateService.instance._dialogCurrentlyOpen = true;
  try {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss update dialog',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 210),
      pageBuilder: (dialogContext, _, __) => Center(
        child: OpenFlixUpdateDialog(info: info),
      ),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  } finally {
    UpdateService.instance._dialogCurrentlyOpen = false;
  }
}

/// Compatibility alias used by manual update checks in **My OpenFlix**.
Future<void> showUpdateBottomSheet(
  BuildContext context, {
  required ReleaseUpdateInfo info,
}) =>
    showUpdateDialog(context, info: info);

class OpenFlixUpdateDialog extends StatefulWidget {
  const OpenFlixUpdateDialog({
    super.key,
    required this.info,
  });

  final ReleaseUpdateInfo info;

  @override
  State<OpenFlixUpdateDialog> createState() => _OpenFlixUpdateDialogState();
}

class _OpenFlixUpdateDialogState extends State<OpenFlixUpdateDialog> {
  static const _kCardBg = Color(0xFF09090B);
  static const _kNotesBg = Color(0xFF121214);
  static const _kSecondaryBg = Color(0xFF18181B);
  static const _kBorder = Color(0xFF27272A);
  static const _kAccent = Color(0xFFE50914);
  static const _kTextPrimary = Color(0xFFF6F6F3);
  static const _kTextMuted = Color(0xA3FFFFFF);

  bool _isDownloading = false;
  int _receivedBytes = 0;
  int _totalBytes = -1;
  String? _downloadError;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel('dialog_closed');
    super.dispose();
  }

  void _onLater() {
    HapticFeedback.selectionClick();
    _cancelToken?.cancel('user_later');
    UpdateService.instance.dismissForCurrentSession(widget.info.cleanVersion);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onUpdateNow() async {
    if (_isDownloading) return;
    HapticFeedback.lightImpact();
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _isDownloading = true;
      _receivedBytes = 0;
      _totalBytes = widget.info.assetSizeBytes ?? -1;
      _downloadError = null;
    });

    try {
      final started = await UpdateService.instance.downloadAndInstallApk(
        widget.info,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
          });
        },
      );
      if (!mounted) return;
      if (token.isCancelled) {
        setState(() => _isDownloading = false);
        return;
      }
      if (started) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isDownloading = false;
          _downloadError = "Couldn't open the installer. Try again.";
        });
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || !mounted) return;
      final mapped = UserError.from(e, logTag: 'UpdateDialog.download');
      setState(() {
        _isDownloading = false;
        _downloadError = mapped.message;
      });
    } catch (e) {
      if (!mounted) return;
      final mapped = UserError.from(e, logTag: 'UpdateDialog.download');
      setState(() {
        _isDownloading = false;
        _downloadError = mapped.message;
      });
    }
  }

  double? get _progressFraction {
    if (_totalBytes <= 0) return null;
    return (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
  }

  String _formatBytesMb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final notes = widget.info.parsedNotes;
    final versionTransition =
        '${widget.info.installedDisplayTag} → ${widget.info.displayTag}';

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 348),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBorder, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Row: UPDATE AVAILABLE badge + version transition chip ──
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1FE50914),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0x55E50914),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'UPDATE AVAILABLE',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: const Color(0xFFFF6B72),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kSecondaryBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kBorder, width: 1),
                    ),
                    child: Text(
                      versionTransition,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _kTextPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Title ──
              Text(
                'New version ready',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.45,
                  height: 1.15,
                  color: _kTextPrimary,
                ),
              ),

              if (widget.info.formattedSizeMb != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Signed Android package · ${widget.info.formattedSizeMb}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _kTextMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ── Parsed Release Notes (bounded maxHeight: 220, scrollable) ──
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kNotesBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder, width: 1),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < notes.length; i++) ...[
                        if (i > 0)
                          SizedBox(height: notes[i].isHeading ? 10 : 7),
                        if (notes[i].isHeading)
                          Text(
                            notes[i].text.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.65,
                              color: _kTextMuted,
                            ),
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 13,
                                  color: Color(0xFF4ADE80),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notes[i].text,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    height: 1.45,
                                    color: const Color(0xFFE4E4E7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Live Download Progress or Inline Error ──
              if (_isDownloading) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progressFraction,
                    minHeight: 5,
                    backgroundColor: _kBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _totalBytes > 0
                          ? '${_formatBytesMb(_receivedBytes)} / ${_formatBytesMb(_totalBytes)}'
                          : 'Downloading update...',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: _kTextMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (_progressFraction != null)
                      Text(
                        '${(_progressFraction! * 100).round()}%',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ] else if (_downloadError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _downloadError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFF6B72),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // ── Action Row: Later (secondary) + Update Now (primary #E50914) ──
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: _kSecondaryBg,
                      shape: const StadiumBorder(
                        side: BorderSide(color: _kBorder, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _onLater,
                        child: Container(
                          height: 42,
                          alignment: Alignment.center,
                          child: Text(
                            _isDownloading ? 'Cancel' : 'Later',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: _kTextPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isDownloading) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Material(
                        color: _kAccent,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _onUpdateNow,
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.system_update_alt_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    _downloadError != null
                                        ? 'Retry Update'
                                        : 'Update Now',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
