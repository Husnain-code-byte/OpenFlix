import 'package:dio/dio.dart';

import '../../data/models/manifest_model.dart';
import '../../data/models/meta_model.dart';

abstract interface class AddonRepository {
  Future<ManifestModel> fetchManifest({CancelToken? cancelToken});

  Future<List<MetaModel>> fetchCatalog(
    CatalogItemModel catalog, {
    int skip = 0,
    CancelToken? cancelToken,
  });

  Future<List<MetaModel>> searchCatalog(
    CatalogItemModel catalog,
    String query, {
    CancelToken? cancelToken,
  });
}
