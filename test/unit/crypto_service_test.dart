import 'package:flutter_test/flutter_test.dart';
import 'package:one_auth/src/core/platform/crypto_platform.dart';
import '../mocks/mock_crypto_platform.dart';

void main() {
  group('OneAuthCryptoPlatform & MockCryptoPlatform Tests', () {
    late MockCryptoPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockCryptoPlatform();
      OneAuthCryptoPlatform.instance = mockPlatform;
    });

    test('getAppSigningHash returns mock hash', () async {
      final hash = await OneAuthCryptoPlatform.instance.getAppSigningHash();
      expect(hash, equals('MOCK_SHA256_CERT_HASH_12345'));
    });

    test('generateKeyPair generates and stores mock public key', () async {
      const alias = 'user_device_key_01';
      final pubKey = await OneAuthCryptoPlatform.instance.generateKeyPair(alias);

      expect(pubKey, isNotNull);
      expect(pubKey, contains('MOCK_PUBLIC_KEY_user_device_key_01'));

      final storedKey = await OneAuthCryptoPlatform.instance.getPublicKey(alias);
      expect(storedKey, equals(pubKey));
    });

    test('signTransaction generates verifiable mock signature', () async {
      const alias = 'txn_key_alias';
      const payloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

      await OneAuthCryptoPlatform.instance.generateKeyPair(alias);
      final signature = await OneAuthCryptoPlatform.instance.signTransaction(alias, payloadHash);

      expect(signature, isNotNull);
      expect(signature, contains(alias));
      expect(signature, contains(payloadHash));

      final isValid = await OneAuthCryptoPlatform.instance.verifySignature(alias, payloadHash, signature!);
      expect(isValid, isTrue);
    });

    test('verifySignature fails for invalid payload or signature', () async {
      const alias = 'txn_key_alias';
      const payloadHash = 'hash_a';
      const badHash = 'hash_b';

      await OneAuthCryptoPlatform.instance.generateKeyPair(alias);
      final signature = await OneAuthCryptoPlatform.instance.signTransaction(alias, payloadHash);

      final isValid = await OneAuthCryptoPlatform.instance.verifySignature(alias, badHash, signature!);
      expect(isValid, isFalse);
    });
  });
}
