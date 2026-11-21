import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../domain/models/addon_models.dart';
import 'official_addons_registry.dart';

class CloudStreamRepoService {
  CloudStreamRepoService(this._dio);

  final Dio _dio;

  static final RegExp _shortcodePattern = RegExp(r'^[A-Za-z0-9_-]{3,32}$');
  static final RegExp _githubRepoPattern = RegExp(
    r'^https?://(?:www\.)?github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$',
    caseSensitive: false,
  );

  /// Resolves a raw `.json` URL, a GitHub repository URL, or a CloudStream
  /// shortcode (`cutt.ly/<code>`) into the canonical `repo.json` URL.
  Future<String> resolveRepoUrl(
    String rawInput, {
    CancelToken? cancelToken,
  }) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Repository URL or shortcode cannot be empty.');
    }

    // 1. Check built-in official shortcode registry first for instant resolution
    for (final official in kOfficialCloudStreamRepos) {
      if (official.shortcode.toLowerCase() == trimmed.toLowerCase() ||
          official.repoUrl.toLowerCase() == trimmed.toLowerCase()) {
        return official.repoUrl;
      }
    }

    // 2. CloudStream shortcode -> resolve via https://cutt.ly/<code>
    if (_shortcodePattern.hasMatch(trimmed)) {
      final shortUrl = 'https://cutt.ly/$trimmed';
      final res = await _dio.get<dynamic>(
        shortUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );
      final resolved = res.realUri.toString();
      if (resolved.isNotEmpty && resolved != shortUrl) {
        return resolved;
      }
      return shortUrl;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const FormatException(
        'Enter a valid CloudStream repo.json URL, GitHub URL, or shortcode.',
      );
    }

    // 3. GitHub repo URL -> probe common CloudStream branch manifests
    final ghMatch = _githubRepoPattern.firstMatch(trimmed);
    if (ghMatch != null) {
      final owner = ghMatch.group(1)!;
      final repo = ghMatch.group(2)!;
      final candidates = [
        'https://raw.githubusercontent.com/$owner/$repo/builds/repo.json',
        'https://raw.githubusercontent.com/$owner/$repo/refs/heads/builds/repo.json',
        'https://raw.githubusercontent.com/$owner/$repo/master/repo.json',
        'https://raw.githubusercontent.com/$owner/$repo/main/repo.json',
      ];
      for (final candidate in candidates) {
        try {
          await _getJsonDynamic(candidate, cancelToken: cancelToken);
          return candidate;
        } catch (_) {}
      }
      throw FormatException(
        'Could not locate repo.json in github.com/$owner/$repo (checked builds, master, main).',
      );
    }

    return trimmed;
  }

  Future<dynamic> _getJsonDynamic(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<dynamic>(
      url,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = res.data;
    return raw is String ? jsonDecode(raw) : raw;
  }

  /// Fetches a CloudStream repository manifest (`repo.json`) and indexes all
  /// `plugins.json` lists in parallel, deduplicating by `internalName`.
  Future<AddedCloudStreamRepo> fetchRepoIndex(
    String inputOrUrl, {
    OfficialCloudStreamRepoEntry? official,
    CancelToken? cancelToken,
  }) async {
    final repoUrl = official?.repoUrl ??
        await resolveRepoUrl(inputOrUrl, cancelToken: cancelToken);

    final decoded = await _getJsonDynamic(repoUrl, cancelToken: cancelToken);
    if (decoded is! Map) {
      throw const FormatException('CloudStream repo.json did not return a JSON object.');
    }
    final repoMap = Map<String, dynamic>.from(decoded);

    final pluginLists = ((repoMap['pluginLists'] as List?) ?? const [])
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (pluginLists.isEmpty) {
      throw const FormatException('Repository manifest does not declare any pluginLists.');
    }

    final lists = await Future.wait(
      pluginLists.map((listUrl) async {
        try {
          final rawList =
              await _getJsonDynamic(listUrl, cancelToken: cancelToken);
          if (rawList is! List) return const <Cs3PluginMeta>[];
          return rawList
              .whereType<Map>()
              .map((e) => Cs3PluginMeta.fromJson(Map<String, dynamic>.from(e)))
              .where((p) => p.url.isNotEmpty)
              .toList();
        } catch (_) {
          return const <Cs3PluginMeta>[];
        }
      }),
    );

    final byInternalName = <String, Cs3PluginMeta>{};
    for (final batch in lists) {
      for (final p in batch) {
        final prev = byInternalName[p.internalName];
        if (prev == null || p.version > prev.version) {
          byInternalName[p.internalName] = p;
        }
      }
    }

    final plugins = byInternalName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final id = official?.id ?? _deriveCustomRepoId(repoUrl);

    return AddedCloudStreamRepo(
      id: id,
      name: official?.name ?? (repoMap['name']?.toString() ?? 'CloudStream Repo'),
      description: official?.description ?? repoMap['description'] as String?,
      repoUrl: repoUrl,
      iconUrl: repoMap['iconUrl'] as String?,
      shortcode: official?.shortcode,
      languageBadge: official?.languageBadge,
      isOfficial: official != null,
      pluginLists: pluginLists,
      plugins: plugins,
      lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _deriveCustomRepoId(String repoUrl) {
    final uri = Uri.tryParse(repoUrl);
    final raw = '${uri?.host ?? 'repo'}_${uri?.pathSegments.take(2).join('_') ?? ''}';
    final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_').toLowerCase();
    return 'cs_custom_$clean';
  }
}

final cloudStreamRepoServiceProvider = Provider<CloudStreamRepoService>(
  (ref) => CloudStreamRepoService(ref.watch(dioProvider)),
);
