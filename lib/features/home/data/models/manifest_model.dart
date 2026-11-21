import 'package:equatable/equatable.dart';

class CatalogExtraModel extends Equatable {
  const CatalogExtraModel({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit,
  });

  final String name;
  final bool isRequired;
  final List<String> options;
  final int? optionsLimit;

  factory CatalogExtraModel.fromJson(Map<String, dynamic> j) => CatalogExtraModel(
        name: j['name']?.toString() ?? '',
        isRequired: j['isRequired'] == true,
        options: (j['options'] as List?)?.whereType<String>().toList() ?? const [],
        optionsLimit: (j['optionsLimit'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (isRequired) 'isRequired': true,
        if (options.isNotEmpty) 'options': options,
        if (optionsLimit != null) 'optionsLimit': optionsLimit,
      };

  @override
  List<Object?> get props => [name, isRequired, options, optionsLimit];
}

class ManifestResourceModel extends Equatable {
  const ManifestResourceModel({
    required this.name,
    this.types,
    this.idPrefixes,
  });

  final String name;
  final List<String>? types;
  final List<String>? idPrefixes;

  factory ManifestResourceModel.fromDynamic(dynamic raw) {
    if (raw is String) {
      return ManifestResourceModel(name: raw.trim());
    }
    if (raw is Map<String, dynamic>) {
      return ManifestResourceModel(
        name: raw['name']?.toString().trim() ?? '',
        types: (raw['types'] as List?)?.whereType<String>().toList(),
        idPrefixes: (raw['idPrefixes'] as List?)?.whereType<String>().toList(),
      );
    }
    if (raw is Map) {
      return ManifestResourceModel(
        name: raw['name']?.toString().trim() ?? '',
        types: (raw['types'] as List?)?.whereType<String>().toList(),
        idPrefixes: (raw['idPrefixes'] as List?)?.whereType<String>().toList(),
      );
    }
    return const ManifestResourceModel(name: '');
  }

  dynamic toJson() {
    if (types == null && idPrefixes == null) return name;
    return {
      'name': name,
      if (types != null) 'types': types,
      if (idPrefixes != null) 'idPrefixes': idPrefixes,
    };
  }

  @override
  List<Object?> get props => [name, types, idPrefixes];
}

class ManifestBehaviorHints extends Equatable {
  const ManifestBehaviorHints({
    this.adult = false,
    this.p2p = false,
    this.configurable = false,
    this.configurationRequired = false,
  });

  final bool adult;
  final bool p2p;
  final bool configurable;
  final bool configurationRequired;

  factory ManifestBehaviorHints.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ManifestBehaviorHints();
    return ManifestBehaviorHints(
      adult: j['adult'] == true,
      p2p: j['p2p'] == true,
      configurable: j['configurable'] == true,
      configurationRequired: j['configurationRequired'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        if (adult) 'adult': true,
        if (p2p) 'p2p': true,
        if (configurable) 'configurable': true,
        if (configurationRequired) 'configurationRequired': true,
      };

  @override
  List<Object?> get props => [adult, p2p, configurable, configurationRequired];
}

class CatalogItemModel extends Equatable {
  const CatalogItemModel({
    required this.id,
    required this.type,
    required this.name,
    this.extra = const [],
    this.extraSupported = const [],
    this.extraRequired = const [],
    this.showInHome = true,
    this.addonId,
    this.addonName,
  });

  final String id;
  final String type;
  final String name;
  final List<CatalogExtraModel> extra;
  final List<String> extraSupported;
  final List<String> extraRequired;
  final bool showInHome;
  final String? addonId;
  final String? addonName;

  /// Base Stremio catalog identifier (`$type/$id`) without addon namespace.
  String get baseKey => '$type/$id';

  /// Unique shelf key across built-in and multiple custom Stremio addons.
  String get key => addonId != null ? '$addonId::$type/$id' : '$type/$id';

  bool get hasRequiredExtra =>
      extra.any((e) => e.isRequired) || extraRequired.isNotEmpty;

  /// True when this catalog accepts a `search` query parameter in Stremio v3.
  bool get supportsSearch =>
      extra.any((e) => e.name == 'search') ||
      extraSupported.contains('search') ||
      extraRequired.contains('search');

  String get typeLabel =>
      type == 'series' ? 'Series' : type == 'movie' ? 'Movies' : type;

  CatalogItemModel copyWithAddon(String addonId, String addonName, {String? customName}) =>
      CatalogItemModel(
        id: id,
        type: type,
        name: (customName != null && customName.trim().isNotEmpty) ? customName.trim() : name,
        extra: extra,
        extraSupported: extraSupported,
        extraRequired: extraRequired,
        showInHome: showInHome,
        addonId: addonId,
        addonName: addonName,
      );

  factory CatalogItemModel.fromJson(Map<String, dynamic> j) => CatalogItemModel(
        id: j['id'].toString(),
        type: j['type'].toString(),
        name: (j['name'] as String?)?.trim().isNotEmpty == true
            ? j['name'] as String
            : j['id'].toString(),
        extra: (j['extra'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CatalogExtraModel.fromJson)
                .toList() ??
            const [],
        extraSupported:
            (j['extraSupported'] as List?)?.whereType<String>().toList() ?? const [],
        extraRequired:
            (j['extraRequired'] as List?)?.whereType<String>().toList() ?? const [],
        showInHome: j['showInHome'] != false,
        addonId: j['addonId'] as String?,
        addonName: j['addonName'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (extra.isNotEmpty) 'extra': extra.map((e) => e.toJson()).toList(),
        if (extraSupported.isNotEmpty) 'extraSupported': extraSupported,
        if (extraRequired.isNotEmpty) 'extraRequired': extraRequired,
        if (!showInHome) 'showInHome': false,
        if (addonId != null) 'addonId': addonId,
        if (addonName != null) 'addonName': addonName,
      };

  @override
  List<Object?> get props => [
        id,
        type,
        name,
        extra,
        extraSupported,
        extraRequired,
        showInHome,
        addonId,
        addonName,
      ];
}

class ManifestModel extends Equatable {
  const ManifestModel({
    required this.id,
    required this.version,
    required this.name,
    this.description,
    this.logo,
    this.background,
    this.types = const [],
    this.resources = const [],
    this.resourceDefs = const [],
    this.idPrefixes = const [],
    this.catalogs = const [],
    this.behaviorHints = const ManifestBehaviorHints(),
  });

  final String id;
  final String version;
  final String name;
  final String? description;
  final String? logo;
  final String? background;
  final List<String> types;
  final List<String> resources;
  final List<ManifestResourceModel> resourceDefs;
  final List<String> idPrefixes;
  final List<CatalogItemModel> catalogs;
  final ManifestBehaviorHints behaviorHints;

  /// Checks whether this manifest declares [resourceName] (e.g. `'stream'`,
  /// `'meta'`, `'subtitles'`, `'catalog'`) for optional [type] and [id] prefix.
  bool supportsResource(String resourceName, {String? type, String? id}) {
    final matchingDefs = resourceDefs.where((r) => r.name == resourceName).toList();
    if (matchingDefs.isNotEmpty) {
      for (final def in matchingDefs) {
        final effectiveTypes = def.types ?? types;
        if (type != null && effectiveTypes.isNotEmpty && !effectiveTypes.contains(type)) {
          continue;
        }
        final effectivePrefixes = def.idPrefixes ?? idPrefixes;
        if (id != null &&
            effectivePrefixes.isNotEmpty &&
            !effectivePrefixes.any((prefix) => id.startsWith(prefix))) {
          continue;
        }
        return true;
      }
      return false;
    }

    if (!resources.contains(resourceName)) return false;
    if (type != null && types.isNotEmpty && !types.contains(type)) {
      return false;
    }
    if (id != null &&
        idPrefixes.isNotEmpty &&
        !idPrefixes.any((prefix) => id.startsWith(prefix))) {
      return false;
    }
    return true;
  }

  factory ManifestModel.fromJson(Map<String, dynamic> j) {
    final rawResources = j['resources'] as List?;
    final defs = rawResources
            ?.map(ManifestResourceModel.fromDynamic)
            .where((r) => r.name.isNotEmpty)
            .toList() ??
        const <ManifestResourceModel>[];
    final names = defs.map((d) => d.name).toList();

    return ManifestModel(
      id: j['id']?.toString() ?? 'unknown',
      version: j['version']?.toString() ?? '0.0.0',
      name: j['name']?.toString() ?? 'Addon',
      description: j['description'] as String?,
      logo: (j['logo'] as String?) ?? (j['icon'] as String?),
      background: j['background'] as String?,
      types: (j['types'] as List?)?.whereType<String>().toList() ?? const [],
      resources: names,
      resourceDefs: defs,
      idPrefixes: (j['idPrefixes'] as List?)?.whereType<String>().toList() ?? const [],
      catalogs: (j['catalogs'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .where((c) => c['id'] != null && c['type'] != null)
              .map(CatalogItemModel.fromJson)
              .toList() ??
          const [],
      behaviorHints: ManifestBehaviorHints.fromJson(
        j['behaviorHints'] is Map<String, dynamic>
            ? j['behaviorHints'] as Map<String, dynamic>
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'name': name,
        if (description != null) 'description': description,
        if (logo != null) 'logo': logo,
        if (background != null) 'background': background,
        if (types.isNotEmpty) 'types': types,
        'resources': resourceDefs.isNotEmpty
            ? resourceDefs.map((r) => r.toJson()).toList()
            : resources,
        if (idPrefixes.isNotEmpty) 'idPrefixes': idPrefixes,
        'catalogs': catalogs.map((c) => c.toJson()).toList(),
        'behaviorHints': behaviorHints.toJson(),
      };

  @override
  List<Object?> get props => [
        id,
        version,
        name,
        types,
        resources,
        resourceDefs,
        idPrefixes,
        catalogs,
        behaviorHints,
      ];
}
