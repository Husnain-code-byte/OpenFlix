import 'package:equatable/equatable.dart';

import '../../../home/data/models/manifest_model.dart';

enum AddonArchitecture {
  stremio('Stremio v3', 'HTTP Manifest Protocol'),
  cloudstream('CloudStream', 'Native .cs3 Extension Repo');

  const AddonArchitecture(this.shortLabel, this.protocolLabel);
  final String shortLabel;
  final String protocolLabel;
}

/// Destination top-nav screens where custom Stremio catalog rows can be placed.
enum AddonTargetScreen {
  home('Home', 'Main discovery feed'),
  movies('Movies', 'Films screen'),
  tvShows('TV Shows', 'Series screen'),
  anime('Anime', 'Anime hub'),
  categories('Categories', 'Genre & curated shelves');

  const AddonTargetScreen(this.label, this.subtitle);
  final String label;
  final String subtitle;

  static AddonTargetScreen? fromName(String raw) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}

enum CatalogShelfPosition {
  belowBuiltIn('Below Built-in Shelves'),
  aboveBuiltIn('Pinned to Top');

  const CatalogShelfPosition(this.label);
  final String label;

  static CatalogShelfPosition fromName(String? raw) =>
      raw == aboveBuiltIn.name ? aboveBuiltIn : belowBuiltIn;
}

class CatalogPlacement extends Equatable {
  const CatalogPlacement({
    required this.catalogKey,
    this.enabled = true,
    this.targetScreens = const {},
    this.position = CatalogShelfPosition.belowBuiltIn,
    this.customTitle,
  });

  /// Un-namespaced Stremio catalog key (`$type/$id`).
  final String catalogKey;
  final bool enabled;
  final Set<AddonTargetScreen> targetScreens;
  final CatalogShelfPosition position;
  final String? customTitle;

  CatalogPlacement copyWith({
    bool? enabled,
    Set<AddonTargetScreen>? targetScreens,
    CatalogShelfPosition? position,
    String? customTitle,
  }) =>
      CatalogPlacement(
        catalogKey: catalogKey,
        enabled: enabled ?? this.enabled,
        targetScreens: targetScreens ?? this.targetScreens,
        position: position ?? this.position,
        customTitle: customTitle ?? this.customTitle,
      );

  factory CatalogPlacement.fromJson(Map<String, dynamic> j) => CatalogPlacement(
        catalogKey: j['catalogKey']?.toString() ?? '',
        enabled: j['enabled'] != false,
        targetScreens: ((j['targetScreens'] as List?) ?? const [])
            .whereType<String>()
            .map(AddonTargetScreen.fromName)
            .whereType<AddonTargetScreen>()
            .toSet(),
        position: CatalogShelfPosition.fromName(j['position'] as String?),
        customTitle: j['customTitle'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'catalogKey': catalogKey,
        'enabled': enabled,
        'targetScreens': targetScreens.map((s) => s.name).toList(),
        'position': position.name,
        if (customTitle != null) 'customTitle': customTitle,
      };

  @override
  List<Object?> get props => [
        catalogKey,
        enabled,
        targetScreens,
        position,
        customTitle,
      ];
}

class InstalledStremioAddon extends Equatable {
  const InstalledStremioAddon({
    required this.id,
    required this.manifestUrl,
    required this.baseUrl,
    required this.manifest,
    this.enabled = true,
    this.orderIndex = 0,
    this.isOfficial = false,
    this.includeInSearch = true,
    this.catalogPlacements = const [],
    this.installedAtMs = 0,
    this.lastUpdatedAtMs = 0,
  });

  final String id;
  final String manifestUrl;
  final String baseUrl;
  final ManifestModel manifest;
  final bool enabled;
  final int orderIndex;
  final bool isOfficial;
  final bool includeInSearch;
  final List<CatalogPlacement> catalogPlacements;
  final int installedAtMs;
  final int lastUpdatedAtMs;

  bool get configurable =>
      manifest.behaviorHints.configurable ||
      manifest.behaviorHints.configurationRequired;

  bool get supportsCatalogs => manifest.catalogs.isNotEmpty;
  bool get supportsStreams => manifest.supportsResource('stream');
  bool get supportsMeta => manifest.supportsResource('meta');
  bool get supportsSubtitles => manifest.supportsResource('subtitles');

  Set<AddonTargetScreen> get effectiveTargets {
    final out = <AddonTargetScreen>{};
    for (final p in catalogPlacements) {
      if (p.enabled) out.addAll(p.targetScreens);
    }
    return out;
  }

  CatalogPlacement? placementFor(CatalogItemModel catalog) {
    for (final p in catalogPlacements) {
      if (p.catalogKey == catalog.baseKey) return p;
    }
    return null;
  }

  CatalogShelfPosition get primaryShelfPosition {
    for (final p in catalogPlacements) {
      if (p.enabled && p.targetScreens.isNotEmpty) return p.position;
    }
    return CatalogShelfPosition.belowBuiltIn;
  }

  InstalledStremioAddon copyWith({
    String? manifestUrl,
    String? baseUrl,
    ManifestModel? manifest,
    bool? enabled,
    int? orderIndex,
    bool? isOfficial,
    bool? includeInSearch,
    List<CatalogPlacement>? catalogPlacements,
    int? lastUpdatedAtMs,
  }) =>
      InstalledStremioAddon(
        id: id,
        manifestUrl: manifestUrl ?? this.manifestUrl,
        baseUrl: baseUrl ?? this.baseUrl,
        manifest: manifest ?? this.manifest,
        enabled: enabled ?? this.enabled,
        orderIndex: orderIndex ?? this.orderIndex,
        isOfficial: isOfficial ?? this.isOfficial,
        includeInSearch: includeInSearch ?? this.includeInSearch,
        catalogPlacements: catalogPlacements ?? this.catalogPlacements,
        installedAtMs: installedAtMs,
        lastUpdatedAtMs: lastUpdatedAtMs ?? this.lastUpdatedAtMs,
      );

  factory InstalledStremioAddon.fromJson(Map<String, dynamic> j) =>
      InstalledStremioAddon(
        id: j['id']?.toString() ?? '',
        manifestUrl: j['manifestUrl']?.toString() ?? '',
        baseUrl: j['baseUrl']?.toString() ?? '',
        manifest: ManifestModel.fromJson(
          (j['manifest'] as Map<String, dynamic>?) ?? const {},
        ),
        enabled: j['enabled'] != false,
        orderIndex: (j['orderIndex'] as num?)?.toInt() ?? 0,
        isOfficial: j['isOfficial'] == true,
        includeInSearch: j['includeInSearch'] != false,
        catalogPlacements: ((j['catalogPlacements'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CatalogPlacement.fromJson)
            .toList(),
        installedAtMs: (j['installedAtMs'] as num?)?.toInt() ?? 0,
        lastUpdatedAtMs: (j['lastUpdatedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'manifestUrl': manifestUrl,
        'baseUrl': baseUrl,
        'manifest': manifest.toJson(),
        'enabled': enabled,
        'orderIndex': orderIndex,
        'isOfficial': isOfficial,
        'includeInSearch': includeInSearch,
        'catalogPlacements': catalogPlacements.map((p) => p.toJson()).toList(),
        'installedAtMs': installedAtMs,
        'lastUpdatedAtMs': lastUpdatedAtMs,
      };

  @override
  List<Object?> get props => [
        id,
        manifestUrl,
        baseUrl,
        manifest,
        enabled,
        orderIndex,
        isOfficial,
        includeInSearch,
        catalogPlacements,
        installedAtMs,
        lastUpdatedAtMs,
      ];
}

class OfficialCloudStreamRepoEntry extends Equatable {
  const OfficialCloudStreamRepoEntry({
    required this.id,
    required this.name,
    required this.shortcode,
    required this.languageBadge,
    required this.description,
    required this.repoUrl,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String shortcode;
  final String languageBadge;
  final String description;
  final String repoUrl;
  final List<String> tags;

  @override
  List<Object?> get props => [id, name, shortcode, repoUrl];
}

class OfficialStremioAddonEntry extends Equatable {
  const OfficialStremioAddonEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.manifestUrl,
    this.configureUrl,
    this.requiresConfiguration = false,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String description;
  final String manifestUrl;
  final String? configureUrl;
  final bool requiresConfiguration;
  final List<String> tags;

  @override
  List<Object?> get props => [id, name, manifestUrl];
}

class Cs3PluginMeta extends Equatable {
  const Cs3PluginMeta({
    required this.name,
    required this.internalName,
    required this.url,
    required this.version,
    this.apiVersion = 1,
    this.tvTypes = const [],
    this.language = 'en',
    this.status = 1,
    this.iconUrl,
    this.authors = const [],
    this.description,
    this.fileSize = 0,
    this.fileHash,
    this.repositoryUrl,
  });

  final String name;
  final String internalName;
  final String url;
  final int version;
  final int apiVersion;
  final List<String> tvTypes;
  final String language;
  final int status;
  final String? iconUrl;
  final List<String> authors;
  final String? description;
  final int fileSize;
  final String? fileHash;
  final String? repositoryUrl;

  bool get isWorking => status == 1 && url.isNotEmpty;
  bool get isNsfw =>
      tvTypes.any((t) => t.trim().toLowerCase() == 'nsfw');

  int get fileSizeKb => fileSize > 0 ? (fileSize / 1024).ceil() : 0;

  factory Cs3PluginMeta.fromJson(Map<String, dynamic> j) => Cs3PluginMeta(
        name: j['name']?.toString() ?? j['internalName']?.toString() ?? 'Plugin',
        internalName:
            j['internalName']?.toString() ?? j['name']?.toString() ?? 'plugin',
        url: j['url']?.toString() ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        apiVersion: (j['apiVersion'] as num?)?.toInt() ?? 1,
        tvTypes: (j['tvTypes'] as List?)?.whereType<String>().toList() ?? const [],
        language: j['language']?.toString() ?? 'en',
        status: (j['status'] as num?)?.toInt() ?? 1,
        iconUrl: j['iconUrl'] as String?,
        authors: (j['authors'] as List?)?.whereType<String>().toList() ?? const [],
        description: j['description'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        fileHash: j['fileHash'] as String?,
        repositoryUrl: j['repositoryUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'internalName': internalName,
        'url': url,
        'version': version,
        'apiVersion': apiVersion,
        if (tvTypes.isNotEmpty) 'tvTypes': tvTypes,
        'language': language,
        'status': status,
        if (iconUrl != null) 'iconUrl': iconUrl,
        if (authors.isNotEmpty) 'authors': authors,
        if (description != null) 'description': description,
        'fileSize': fileSize,
        if (fileHash != null) 'fileHash': fileHash,
        if (repositoryUrl != null) 'repositoryUrl': repositoryUrl,
      };

  @override
  List<Object?> get props => [internalName, url, version, status, language, tvTypes];
}

class AddedCloudStreamRepo extends Equatable {
  const AddedCloudStreamRepo({
    required this.id,
    required this.name,
    required this.repoUrl,
    this.description,
    this.iconUrl,
    this.shortcode,
    this.languageBadge,
    this.isOfficial = false,
    this.pluginLists = const [],
    this.plugins = const [],
    this.lastSyncedAtMs = 0,
  });

  final String id;
  final String name;
  final String repoUrl;
  final String? description;
  final String? iconUrl;
  final String? shortcode;
  final String? languageBadge;
  final bool isOfficial;
  final List<String> pluginLists;
  final List<Cs3PluginMeta> plugins;
  final int lastSyncedAtMs;

  AddedCloudStreamRepo copyWith({
    String? name,
    String? description,
    String? iconUrl,
    List<String>? pluginLists,
    List<Cs3PluginMeta>? plugins,
    int? lastSyncedAtMs,
  }) =>
      AddedCloudStreamRepo(
        id: id,
        name: name ?? this.name,
        repoUrl: repoUrl,
        description: description ?? this.description,
        iconUrl: iconUrl ?? this.iconUrl,
        shortcode: shortcode,
        languageBadge: languageBadge,
        isOfficial: isOfficial,
        pluginLists: pluginLists ?? this.pluginLists,
        plugins: plugins ?? this.plugins,
        lastSyncedAtMs: lastSyncedAtMs ?? this.lastSyncedAtMs,
      );

  factory AddedCloudStreamRepo.fromJson(Map<String, dynamic> j) =>
      AddedCloudStreamRepo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'CloudStream Repo',
        repoUrl: j['repoUrl']?.toString() ?? '',
        description: j['description'] as String?,
        iconUrl: j['iconUrl'] as String?,
        shortcode: j['shortcode'] as String?,
        languageBadge: j['languageBadge'] as String?,
        isOfficial: j['isOfficial'] == true,
        pluginLists:
            (j['pluginLists'] as List?)?.whereType<String>().toList() ?? const [],
        plugins: ((j['plugins'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Cs3PluginMeta.fromJson)
            .toList(),
        lastSyncedAtMs: (j['lastSyncedAtMs'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'repoUrl': repoUrl,
        if (description != null) 'description': description,
        if (iconUrl != null) 'iconUrl': iconUrl,
        if (shortcode != null) 'shortcode': shortcode,
        if (languageBadge != null) 'languageBadge': languageBadge,
        'isOfficial': isOfficial,
        'pluginLists': pluginLists,
        'plugins': plugins.map((p) => p.toJson()).toList(),
        'lastSyncedAtMs': lastSyncedAtMs,
      };

  @override
  List<Object?> get props => [
        id,
        name,
        repoUrl,
        isOfficial,
        pluginLists,
        plugins,
        lastSyncedAtMs,
      ];
}

enum Cs3LoadStatus {
  pending,
  downloading,
  loaded,
  failed;

  static Cs3LoadStatus fromName(String? raw) => values.firstWhere(
        (v) => v.name == raw,
        orElse: () => Cs3LoadStatus.pending,
      );
}

class InstalledCs3Plugin extends Equatable {
  const InstalledCs3Plugin({
    required this.uid,
    required this.repoId,
    required this.internalName,
    required this.name,
    required this.downloadUrl,
    this.localFilePath,
    this.version = 0,
    this.apiVersion = 1,
    this.tvTypes = const [],
    this.language = 'en',
    this.iconUrl,
    this.fileSize = 0,
    this.fileHash,
    this.enabled = true,
    this.loadStatus = Cs3LoadStatus.pending,
    this.lastError,
    this.registeredProviderNames = const [],
  });

  final String uid;
  final String repoId;
  final String internalName;
  final String name;
  final String downloadUrl;
  final String? localFilePath;
  final int version;
  final int apiVersion;
  final List<String> tvTypes;
  final String language;
  final String? iconUrl;
  final int fileSize;
  final String? fileHash;
  final bool enabled;
  final Cs3LoadStatus loadStatus;
  final String? lastError;
  final List<String> registeredProviderNames;

  static String makeUid(String repoId, String internalName) =>
      '$repoId::$internalName';

  InstalledCs3Plugin copyWith({
    String? downloadUrl,
    String? localFilePath,
    int? version,
    bool? enabled,
    Cs3LoadStatus? loadStatus,
    String? lastError,
    bool clearError = false,
    List<String>? registeredProviderNames,
  }) =>
      InstalledCs3Plugin(
        uid: uid,
        repoId: repoId,
        internalName: internalName,
        name: name,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        localFilePath: localFilePath ?? this.localFilePath,
        version: version ?? this.version,
        apiVersion: apiVersion,
        tvTypes: tvTypes,
        language: language,
        iconUrl: iconUrl,
        fileSize: fileSize,
        fileHash: fileHash,
        enabled: enabled ?? this.enabled,
        loadStatus: loadStatus ?? this.loadStatus,
        lastError: clearError ? null : (lastError ?? this.lastError),
        registeredProviderNames:
            registeredProviderNames ?? this.registeredProviderNames,
      );

  factory InstalledCs3Plugin.fromJson(Map<String, dynamic> j) =>
      InstalledCs3Plugin(
        uid: j['uid']?.toString() ?? '',
        repoId: j['repoId']?.toString() ?? '',
        internalName: j['internalName']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        downloadUrl: j['downloadUrl']?.toString() ?? '',
        localFilePath: j['localFilePath'] as String?,
        version: (j['version'] as num?)?.toInt() ?? 0,
        apiVersion: (j['apiVersion'] as num?)?.toInt() ?? 1,
        tvTypes: (j['tvTypes'] as List?)?.whereType<String>().toList() ?? const [],
        language: j['language']?.toString() ?? 'en',
        iconUrl: j['iconUrl'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt() ?? 0,
        fileHash: j['fileHash'] as String?,
        enabled: j['enabled'] != false,
        loadStatus: Cs3LoadStatus.fromName(j['loadStatus'] as String?),
        lastError: j['lastError'] as String?,
        registeredProviderNames:
            (j['registeredProviderNames'] as List?)?.whereType<String>().toList() ??
                const [],
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'repoId': repoId,
        'internalName': internalName,
        'name': name,
        'downloadUrl': downloadUrl,
        if (localFilePath != null) 'localFilePath': localFilePath,
        'version': version,
        'apiVersion': apiVersion,
        if (tvTypes.isNotEmpty) 'tvTypes': tvTypes,
        'language': language,
        if (iconUrl != null) 'iconUrl': iconUrl,
        'fileSize': fileSize,
        if (fileHash != null) 'fileHash': fileHash,
        'enabled': enabled,
        'loadStatus': loadStatus.name,
        if (lastError != null) 'lastError': lastError,
        if (registeredProviderNames.isNotEmpty)
          'registeredProviderNames': registeredProviderNames,
      };

  @override
  List<Object?> get props => [
        uid,
        repoId,
        internalName,
        version,
        localFilePath,
        enabled,
        loadStatus,
        lastError,
        registeredProviderNames,
      ];
}

class AddonsStoreState extends Equatable {
  const AddonsStoreState({
    this.schemaVersion = 1,
    this.safetyAccepted = false,
    this.showNsfw = false,
    this.stremioAddons = const [],
    this.cloudStreamRepos = const [],
    this.installedCs3Plugins = const [],
  });

  final int schemaVersion;
  final bool safetyAccepted;
  final bool showNsfw;
  final List<InstalledStremioAddon> stremioAddons;
  final List<AddedCloudStreamRepo> cloudStreamRepos;
  final List<InstalledCs3Plugin> installedCs3Plugins;

  int get totalInstalledEntryCount =>
      stremioAddons.length + cloudStreamRepos.length;

  bool get hasAnyStreamSource {
    final hasStremioStream =
        stremioAddons.any((a) => a.enabled && a.supportsStreams);
    final hasCs3Stream = installedCs3Plugins.any(
      (p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded,
    );
    return hasStremioStream || hasCs3Stream;
  }

  AddonsStoreState copyWith({
    bool? safetyAccepted,
    bool? showNsfw,
    List<InstalledStremioAddon>? stremioAddons,
    List<AddedCloudStreamRepo>? cloudStreamRepos,
    List<InstalledCs3Plugin>? installedCs3Plugins,
  }) =>
      AddonsStoreState(
        schemaVersion: schemaVersion,
        safetyAccepted: safetyAccepted ?? this.safetyAccepted,
        showNsfw: showNsfw ?? this.showNsfw,
        stremioAddons: stremioAddons ?? this.stremioAddons,
        cloudStreamRepos: cloudStreamRepos ?? this.cloudStreamRepos,
        installedCs3Plugins: installedCs3Plugins ?? this.installedCs3Plugins,
      );

  factory AddonsStoreState.fromJson(Map<String, dynamic> j) => AddonsStoreState(
        schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
        safetyAccepted: j['safetyAccepted'] == true,
        showNsfw: j['showNsfw'] == true,
        stremioAddons: ((j['stremioAddons'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InstalledStremioAddon.fromJson)
            .toList(),
        cloudStreamRepos: ((j['cloudStreamRepos'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AddedCloudStreamRepo.fromJson)
            .toList(),
        installedCs3Plugins: ((j['installedCs3Plugins'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(InstalledCs3Plugin.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'safetyAccepted': safetyAccepted,
        'showNsfw': showNsfw,
        'stremioAddons': stremioAddons.map((a) => a.toJson()).toList(),
        'cloudStreamRepos': cloudStreamRepos.map((r) => r.toJson()).toList(),
        'installedCs3Plugins':
            installedCs3Plugins.map((p) => p.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        schemaVersion,
        safetyAccepted,
        showNsfw,
        stremioAddons,
        cloudStreamRepos,
        installedCs3Plugins,
      ];
}
