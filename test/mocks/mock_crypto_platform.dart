import 'dart:async';
import 'package:one_auth/src/core/platform/crypto_platform.dart';

/// Mock implementation of [OneAuthCryptoPlatform] for automated unit and widget testing.
class MockCryptoPlatform implements OneAuthCryptoPlatform {
  final Map<String, String> _keys = {};
  String? mockSigningHash = 'MOCK_SHA256_CERT_HASH_12345';

  @override
  Future<String?> getAppSigningHash() async {
    return mockSigningHash;
  }

  @override
  Future<String?> generateKeyPair(String alias) async {
    final mockPubKey = 'MOCK_PUBLIC_KEY_$alias';
    _keys[alias] = mockPubKey;
    return mockPubKey;
  }

  @override
  Future<String?> signTransaction(String alias, String payloadHash) async {
    if (!_keys.containsKey(alias)) {
      return null;
    }
    return 'MOCK_SIG_${alias}_$payloadHash';
  }

  @override
  Future<bool> verifySignature(String alias, String payloadHash, String signature) async {
    final expected = 'MOCK_SIG_${alias}_$payloadHash';
    return signature == expected;
  }

  @override
  Future<String?> getPublicKey(String alias) async {
    return _keys[alias];
  }
}
