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
          'Authorization' : 'Bearer eyJraWQiOiJydmwtb25lLWF1dGhlbnRpY2F0b3Itand0LWtleSIsImFsZyI6IlJTMjU2In0.eyJhcHBfcGFja2FnZV9pZCI6ImNvbS5kaGFrYWJhbmsuYXBwIiwic3ViIjoiMjVhNWNmYzUtZTBkZi00YjlmLTg0MWMtMWY5Njg5NmM5NDQ3Iiwic2NvcGUiOiJzZGs6dXNlIiwiaXNzIjoib25lLWF1dGhlbnRpY2F0b3IiLCJjbGllbnRfdXVpZCI6IjI1YTVjZmM1LWUwZGYtNGI5Zi04NDFjLTFmOTY4OTZjOTQ0NyIsImNsaWVudF90eXBlIjoiQkFOSyIsImV4cCI6NDk0NzI3OTM3MiwiaWF0IjoxNzkzNjc5MzcyLCJjbGllbnRfaWQiOiI5NTdkNWJkZDBlM2U0Mjc5In0.dGfjg5QtuB5NYzuZuJtsbvk_cBQvoZu29PgxTO_FJAFiRUOBF_hXfdsi0QTD6AYhrW5IwSedda-23bhKSR7HtoDdivBZU0eBOVjsne7DUBB3QFsUlSBqYQyfuSMDgVGTWSl_c9tRefP_IGP2eU-TYRdbRQ3d6FGXQL4bNleClI8UEp9hmmQyXCGrEbwAJJvv_Xu3mZQ-e82w59sB36T_Er-qOauk6xc0O0rEdPmThBG6nGaTWmBR0w-dPd8VW05_yKWv4v9cG9JPRigMfDb36RgS1ftGDGlK2A-rcxypdHUpgYxPZPP8jLPtV1EZc0DfRjusr5o8DduS_Sp0gaQglA'
        },
      ),
    );

    dio.interceptors.add(DioCacheInterceptor(options: cacheOptions));

    dio.interceptors.add(AuthInterceptor(
      apiKey: apiKey,
      getClientToken: getClientToken,
      // getUserToken: getUserToken, // Todo: need to enable when 'Authorization' commented
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
