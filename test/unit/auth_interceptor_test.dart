import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:one_auth/src/api/auth_interceptor.dart';

void main() {
  group('AuthInterceptor Unit Tests', () {
    test('onRequest injects X-API-KEY and Authorization headers', () async {
      final interceptor = AuthInterceptor(
        apiKey: 'TEST_API_KEY_123',
        getClientToken: () async => 'CLIENT_TOKEN_456',
        getUserToken: () async => 'USER_TOKEN_789',
      );

      final options = RequestOptions(path: '/test-endpoint');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      // Yield event loop for async token retrieval
      await Future.delayed(Duration.zero);

      expect(options.headers['X-API-KEY'], equals('TEST_API_KEY_123'));
      expect(options.headers['Authorization'], equals('Bearer USER_TOKEN_789'));
    });

    test('onRequest invokes onSecurityCheck callback', () async {
      bool securityChecked = false;
      final interceptor = AuthInterceptor(
        onSecurityCheck: () async {
          securityChecked = true;
        },
      );

      final options = RequestOptions(path: '/sensitive-data');
      final handler = RequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      await Future.delayed(Duration.zero);

      expect(securityChecked, isTrue);
    });
  });
}
