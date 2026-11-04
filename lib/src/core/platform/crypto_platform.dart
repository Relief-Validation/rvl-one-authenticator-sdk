import 'dart:async';
import 'crypto_platform_impl.dart';

/// Abstract platform interface for hardware-backed cryptographic operations and platform channel calls.
abstract class OneAuthCryptoPlatform {
  /// Gets the instance of [OneAuthCryptoPlatform]. Defaults to [MethodChannelCryptoPlatform].
  static OneAuthCryptoPlatform instance = MethodChannelCryptoPlatform();

  /// Retrieves the active app's Base64 SHA-256 signing certificate hash.
  Future<String?> getAppSigningHash();

  /// Generates a hardware-backed key pair inside the TEE/Secure Enclave for [alias].
  Future<String?> generateKeyPair(String alias);

  /// Signs a transaction [payloadHash] using the key pair [alias].
  Future<String?> signTransaction(String alias, String payloadHash);

  /// Verifies a [signature] against [payloadHash] using [alias].
  Future<bool> verifySignature(String alias, String payloadHash, String signature);

  /// Retrieves the public key Base64 string for [alias].
  Future<String?> getPublicKey(String alias);
}
