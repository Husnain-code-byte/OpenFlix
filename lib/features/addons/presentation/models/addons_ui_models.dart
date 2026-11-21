import 'package:flutter/foundation.dart';

import '../../data/official_addons_registry.dart';

/// Live URL classification while typing in the Add Addons composer.
enum DetectedInputKindUi {
  empty,
  stremioManifest,
  cloudStreamRepoJson,
  cloudStreamShortcode,
  invalid,
}

@immutable
class DetectedAddonInputUi {
  const DetectedAddonInputUi({
    required this.kind,
    required this.badgeLabel,
    required this.helperText,
    required this.supportsScreenTargets,
    this.normalizedUrl,
  });

  final DetectedInputKindUi kind;
  final String badgeLabel;
  final String helperText;
  final bool supportsScreenTargets;
  final String? normalizedUrl;

  static DetectedAddonInputUi analyze(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const DetectedAddonInputUi(
        kind: DetectedInputKindUi.empty,
        badgeLabel: 'Stremio v3 · CloudStream',
        helperText:
            'Paste a Stremio manifest.json, CloudStream repo.json / GitHub link, or repo shortcode.',
        supportsScreenTargets: true,
      );
    }

    final lower = trimmed.toLowerCase();

    // Check known official CloudStream shortcodes or repo URLs first.
    for (final repo in kOfficialCloudStreamRepos) {
      if (repo.shortcode.toLowerCase() == lower ||
          repo.repoUrl.toLowerCase() == lower) {
        return DetectedAddonInputUi(
          kind: DetectedInputKindUi.cloudStreamShortcode,
          badgeLabel: 'CloudStream Repo',
          helperText:
              '${repo.name} detected · Indexes .cs3 stream providers for Detail & Play.',
          supportsScreenTargets: false,
          normalizedUrl: repo.repoUrl,
        );
      }
    }

    // CloudStream shortcode (single alphanumeric token, e.g. "megix", "phisher")
    if (RegExp(r'^[a-z0-9_-]{3,32}$', caseSensitive: false).hasMatch(trimmed)) {
      return DetectedAddonInputUi(
        kind: DetectedInputKindUi.cloudStreamShortcode,
        badgeLabel: 'CloudStream Shortcode',
        helperText:
            'Stream repository shortcode detected · Resolves .cs3 providers for Detail & Play.',
        supportsScreenTargets: false,
        normalizedUrl: 'https://cutt.ly/$trimmed',
      );
    }

    // CloudStream repo JSON / GitHub / cutt.ly link (anything not a Stremio manifest.json)
    if (lower.endsWith('repo.json') ||
        lower.endsWith('/cs.json') ||
        lower.endsWith('/cnc.json') ||
        lower.endsWith('plugins.json') ||
        lower.contains('cutt.ly/') ||
        (lower.contains('github.com') && !lower.contains('manifest.json')) ||
        (lower.contains('raw.githubusercontent.com') &&
            !lower.contains('manifest.json'))) {
      return DetectedAddonInputUi(
        kind: DetectedInputKindUi.cloudStreamRepoJson,
        badgeLabel: 'CloudStream Repo',
        helperText:
            'CloudStream extension repository detected · Indexes .cs3 stream providers.',
        supportsScreenTargets: false,
        normalizedUrl: trimmed,
      );
    }

    // Stremio manifest URL (https://, http://, stremio://, or bare domain like v3-cinemeta.strem.io)
    final isBareHost = !lower.contains('://') &&
        !lower.contains(' ') &&
        RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}(/.*)?$', caseSensitive: false)
            .hasMatch(trimmed);
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('stremio://') ||
        isBareHost) {
      final normalized = isBareHost
          ? 'https://$trimmed'
          : trimmed.replaceFirst(
              RegExp('^stremio://', caseSensitive: false),
              'https://',
            );
      final uri = Uri.tryParse(normalized);
      final pathLower = uri?.path.toLowerCase() ?? '';
      final withManifest = pathLower.endsWith('/manifest.json') ||
              pathLower == 'manifest.json'
          ? normalized
          : (pathLower.endsWith('/configure')
              ? normalized.replaceFirst(
                  RegExp(r'/configure/?$', caseSensitive: false),
                  '/manifest.json',
                )
              : '${normalized.replaceAll(RegExp(r'/+$'), '')}/manifest.json');
      return DetectedAddonInputUi(
        kind: DetectedInputKindUi.stremioManifest,
        badgeLabel: 'Stremio Manifest v3',
        helperText:
            'Pick destination screens for catalog rows, or select none for a pure stream addon.',
        supportsScreenTargets: true,
        normalizedUrl: withManifest,
      );
    }

    return const DetectedAddonInputUi(
      kind: DetectedInputKindUi.invalid,
      badgeLabel: 'Unrecognized Format',
      helperText:
          'Enter a valid https:// / stremio:// manifest URL, GitHub repo link, or shortcode.',
      supportsScreenTargets: true,
    );
  }
}
