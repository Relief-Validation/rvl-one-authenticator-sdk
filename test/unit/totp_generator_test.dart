import 'package:flutter_test/flutter_test.dart';
import 'package:one_auth/src/core/totp_generator.dart';

void main() {
  group('OneAuthTotpGenerator Unit Tests', () {
    const testSecret = 'JBSWY3DPEHPK3PXP'; // Base32 encoded secret "Hello!"

    test('generateSecret generates valid Base32 string', () {
      final secret = OneAuthTotpGenerator.generateSecret();
      expect(secret, isNotEmpty);
      expect(secret.length, greaterThanOrEqualTo(16));
    });

    test('generateSecretFromNonce creates deterministic secret', () {
      const nonce = 'SGVsbG8gV29ybGQh';
      final secret1 = OneAuthTotpGenerator.generateSecretFromNonce(nonce);
      final secret2 = OneAuthTotpGenerator.generateSecretFromNonce(nonce);

      expect(secret1, equals(secret2));
      expect(secret1, isNotEmpty);
    });

    test('generateCode generates 6-digit TOTP code', () {
      final now = DateTime.utc(2025, 2, 23, 12, 0, 0);
      final code = OneAuthTotpGenerator.generateCode(testSecret, at: now);

      expect(code, isNotNull);
      expect(code.length, equals(6));
      expect(int.tryParse(code), isNotNull);
    });

    test('verifyCode validates correct code and rejects invalid code', () {
      final now = DateTime.utc(2025, 2, 23, 12, 0, 0);
      final validCode = OneAuthTotpGenerator.generateCode(testSecret, at: now);

      final isVerified = OneAuthTotpGenerator.verifyCode(testSecret, validCode, at: now);
      expect(isVerified, isTrue);

      final isInvalidVerified = OneAuthTotpGenerator.verifyCode(testSecret, '000000', at: now);
      // Unless 000000 happens to be the generated code
      if (validCode != '000000') {
        expect(isInvalidVerified, isFalse);
      }
    });

    test('getSecondsRemaining returns value between 1 and 30', () {
      final remaining = OneAuthTotpGenerator.getSecondsRemaining();
      expect(remaining, greaterThanOrEqualTo(1));
      expect(remaining, lessThanOrEqualTo(30));
    });
  });
}
