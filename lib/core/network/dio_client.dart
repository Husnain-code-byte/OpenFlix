import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';

/// Retries idempotent GETs on timeouts / 5xx / 429 with exponential backoff.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxRetries = ApiConstants.maxRetries});
  final Dio _dio;
  final int maxRetries;

  bool _shouldRetry(DioException e) {
    if (e.type == DioExceptionType.cancel) return false;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final code = e.response?.statusCode ?? 0;
    return code >= 500 || code == 429;
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retry_attempt'] as int?) ?? 0;
    if (attempt < maxRetries && _shouldRetry(err)) {
      await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
      final opts = err.requestOptions..extra['retry_attempt'] = attempt + 1;
      try {
        final res = await _dio.fetch<dynamic>(opts);
        return handler.resolve(res);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }
}

Dio buildDio() {
  final dio = Dio(BaseOptions(
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    sendTimeout: ApiConstants.connectTimeout,
    responseType: ResponseType.json,
    headers: const {'Accept': 'application/json'},
  ));
  // Catalog JSON can be hundreds of KB (100 metas × links/cast arrays).
  // Decode it on a background isolate so parsing never drops UI frames.
  dio.transformer = BackgroundTransformer();
  dio.interceptors.add(RetryInterceptor(dio));
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
  }
  return dio;
}

final dioProvider = Provider<Dio>((ref) => buildDio());

/// Thin Stremio addon protocol client.
class StremioAddonClient {
  StremioAddonClient(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> getJson(String url, {CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(url, cancelToken: cancelToken);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Addon returned a non-object JSON payload');
  }
}

final stremioClientProvider =
    Provider<StremioAddonClient>((ref) => StremioAddonClient(ref.watch(dioProvider)));
