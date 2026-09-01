import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';

class AuthInterceptor extends Interceptor {
  final String? apiKey;
  final Future<String?> Function()? getClientToken;
  final Future<String?> Function()? getUserToken;
  final Future<String?> Function()? getAuthenticatorUserId;
  final Future<void> Function()? onSecurityCheck;
  final Future<bool> Function()? onRefreshToken;
  final VoidCallback? onSessionExpired;

  AuthInterceptor({
    this.apiKey,
    this.getClientToken,
    this.getUserToken,
    this.getAuthenticatorUserId,
    this.onSecurityCheck,
    this.onRefreshToken,
    this.onSessionExpired,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    debugPrint('OneAuth Interceptor: Request to ${options.path}');

    // 1. Mandatory Security Check (before anything else)
    if (onSecurityCheck != null) {
      try {
        await onSecurityCheck!();
      } catch (e) {
        debugPrint('OneAuth Interceptor: Security check failed. Blocking request.');
        return handler.reject(
          DioException(
            requestOptions: options,
            error: e,
            type: DioExceptionType.cancel, // Or custom type
          ),
        );
      }
    }

    // Skip token injection for the client authentication endpoint
    if (options.path.contains('/auth/client/token')) {
      debugPrint('OneAuth Interceptor: Skipping token for client auth endpoint');
      return super.onRequest(options, handler);
    }
    
    if (apiKey != null) {
      options.headers['X-API-KEY'] = apiKey;
    }

    final clientToken = getClientToken != null ? await getClientToken!() : null;
    final userToken = getUserToken != null ? await getUserToken!() : null;
    final authenticatorUserId = getAuthenticatorUserId != null ? await getAuthenticatorUserId!() : null;

    // Priority: User Token > Client Token for the Authorization header
    if (userToken != null) {
      debugPrint('OneAuth Interceptor: Injecting User Token into Authorization: ${userToken.substring(0, 10)}...');
      options.headers['Authorization'] = 'Bearer $userToken';
    } else if (clientToken != null) {
      debugPrint('OneAuth Interceptor: Injecting Client Token into Authorization: ${clientToken.substring(0, 10)}...');
      options.headers['Authorization'] = 'Bearer $clientToken';
    } else {
      debugPrint('OneAuth Interceptor: No token available to inject.');
    }

    // Inject Authenticator User ID into Payload (not header)
    if (authenticatorUserId != null) {
      if (options.data is Map<String, dynamic>) {
        final data = options.data as Map<String, dynamic>;
        
        // Per requirement: "in payload, in id: user.id"
        // We include it as 'id' and also 'authenticatorUserId' for server compatibility
        data['id'] = authenticatorUserId;
        if (!data.containsKey('authenticatorUserId')) {
          data['authenticatorUserId'] = authenticatorUserId;
        }
        
        debugPrint('OneAuth Interceptor: Injected $authenticatorUserId into payload');
      }
    }
    
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      debugPrint('OneAuth Interceptor: 401 Unauthorized detected. Attempting seamless retry...');

      // Prevent infinite loops if re-authentication also fails
      if (err.requestOptions.extra['retried'] == true) {
        debugPrint('OneAuth Interceptor: Retry already attempted. Failing.');
        if (onSessionExpired != null) onSessionExpired!();
        return super.onError(err, handler);
      }

      if (onRefreshToken != null) {
        try {
          final success = await onRefreshToken!();
          if (success) {
            debugPrint('OneAuth Interceptor: Token refreshed. Retrying original request...');
            
            // Clone the original request with the updated token and a retry flag
            final options = err.requestOptions;
            options.extra['retried'] = true;
            
            // Re-fetch the updated tokens
            final clientToken = getClientToken != null ? await getClientToken!() : null;
            final userToken = getUserToken != null ? await getUserToken!() : null;
            
            if (userToken != null) {
              options.headers['Authorization'] = 'Bearer $userToken';
            } else if (clientToken != null) {
              options.headers['Authorization'] = 'Bearer $clientToken';
            }

            // Create a new Dio instance to perform the retry without triggering the same interceptor logic
            // or use the current one if we are careful. Here we use the same dio instance.
            final dio = Dio(); // Basic dio for retry to avoid interceptor complexity
            final response = await dio.request(
              options.path,
              data: options.data,
              queryParameters: options.queryParameters,
              options: Options(
                method: options.method,
                headers: options.headers,
                extra: options.extra,
              ),
            );

            return handler.resolve(response);
          }
        } catch (e) {
          debugPrint('OneAuth Interceptor: Failed to refresh token during retry: $e');
        }
      }

      if (onSessionExpired != null) {
        onSessionExpired!();
      }
    }
    super.onError(err, handler);
  }
}
