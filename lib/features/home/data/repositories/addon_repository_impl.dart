import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../anime/data/anilist_addon_repository.dart';
import '../../domain/repositories/addon_repository.dart';
import '../models/manifest_model.dart';
import '../models/meta_model.dart';

/// Generic Stremio v3 catalog addon repository preserving manifest catalog order.
class AddonRepositoryImpl implements AddonRepository {
  AddonRepositoryImpl(
    this._client, {
    String manifestUrl = 'https://v3-cinemeta.strem.io/manifest.json',
  }) : _manifestUrl = manifestUrl,
       baseUrl = ApiConstants.deriveBaseUrl(manifestUrl);

  final StremioAddonClient _client;
  final String _manifestUrl;
  final String baseUrl;

  @override
  Future<ManifestModel> fetchManifest({CancelToken? cancelToken}) async {
    final json = await _client.getJson(_manifestUrl, cancelToken: cancelToken);
    return ManifestModel.fromJson(json);
  }

  @override
  Future<List<MetaModel>> fetchCatalog(
    CatalogItemModel catalog, {
    int skip = 0,
    CancelToken? cancelToken,
  }) async {
    final type = Uri.encodeComponent(catalog.type);
    final id = Uri.encodeComponent(catalog.id);
    final url = skip > 0
        ? '$baseUrl/catalog/$type/$id/skip=$skip.json'
        : '$baseUrl/catalog/$type/$id.json';
    final json = await _client.getJson(url, cancelToken: cancelToken);
    return MetaModel.listFromCatalogJson(json);
  }

  @override
  Future<List<MetaModel>> searchCatalog(
    CatalogItemModel catalog,
    String query, {
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final type = Uri.encodeComponent(catalog.type);
    final id = Uri.encodeComponent(catalog.id);
    final encodedQuery = Uri.encodeComponent(trimmed);
    final url = '$baseUrl/catalog/$type/$id/search=$encodedQuery.json';
    final json = await _client.getJson(url, cancelToken: cancelToken);
    return MetaModel.listFromCatalogJson(json);
  }
}

final addonRepositoryProvider = Provider<AddonRepository>(
  (ref) => AddonRepositoryImpl(ref.watch(stremioClientProvider)),
);

/// Installed Stremio addons queried across the app (e.g., on the Search screen).
/// Additional addons added here automatically contribute their search-capable
/// catalog rows.
final installedAddonsProvider = Provider<List<AddonRepository>>(
  (ref) => [
    ref.watch(aniListAddonRepositoryProvider),
  ],
);
