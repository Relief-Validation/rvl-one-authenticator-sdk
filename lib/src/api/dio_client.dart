import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';

class DioClient {
  late final Dio dio;

  DioClient({
    required String baseUrl,
    String? apiKey,
    Future<String?> Function()? getClientToken,
    Future<String?> Function()? getUserToken,
    Future<String?> Function()? getAuthenticatorUserId,
    Future<void> Function()? onSecurityCheck,
    Future<bool> Function()? onRefreshToken,
    VoidCallback? onSessionExpired,
    CacheStore? cacheStore,
  }) {
    // Default to MemCacheStore if none provided
    final store = cacheStore ?? MemCacheStore();
    
    final cacheOptions = CacheOptions(
      store: store,
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheOptions.defaultCacheKeyBuilder,
      allowPostMethod: false,
    );

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(DioCacheInterceptor(options: cacheOptions));

    dio.interceptors.add(AuthInterceptor(
      apiKey: apiKey,
      getClientToken: getClientToken,
      getUserToken: getUserToken,
      getAuthenticatorUserId: getAuthenticatorUserId,
      onSecurityCheck: onSecurityCheck,
      onRefreshToken: onRefreshToken,
      onSessionExpired: onSessionExpired,
    ));

    dio.interceptors.add(ErrorInterceptor());

    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }
}
