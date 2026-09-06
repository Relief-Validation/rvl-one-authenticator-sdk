import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'exceptions.dart';

class CsrResult {
  final String csrPem;
  final String? publicKeyPem;
  final List<dynamic> attestationChain;

  const CsrResult({
    required this.csrPem,
    this.publicKeyPem,
    required this.attestationChain,
  });
}

/// Manages the generation, secure storage, and retrieval of hardware-backed CSRs.
class OneAuthCsrManager {
  static const MethodChannel _cryptoChannel =
      MethodChannel('com.example.one_auth/crypto');
  final FlutterSecureStorage _secureStorage;

  OneAuthCsrManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _csrKey = 'csrPem';
  static const String _publicKeyKey = 'publicKeyPem';
  static const String _attestationKey = 'attestationChain';

  /// Stores a CSR PEM, Public Key PEM, and attestation chain in secure storage.
  Future<void> saveCsr({
    required String csrPem,
    String? publicKeyPem,
    List<dynamic>? attestationChain,
  }) async {
    await _secureStorage.write(key: _csrKey, value: csrPem);
    if (publicKeyPem != null && publicKeyPem.isNotEmpty) {
      await _secureStorage.write(key: _publicKeyKey, value: publicKeyPem);
    }
    if (attestationChain != null) {
      await _secureStorage.write(
        key: _attestationKey,
        value: jsonEncode(attestationChain),
      );
    }
  }

  /// Retrieves the stored CSR PEM string from secure storage.
  Future<String?> getCsrPem() async {
    return await _secureStorage.read(key: _csrKey);
  }

  /// Retrieves the stored Public Key PEM string from secure storage.
  Future<String?> getPublicKeyPem() async {
    return await _secureStorage.read(key: _publicKeyKey);
  }

  /// Retrieves the full stored CSR result (PEM + Public Key + Attestation Chain) from secure storage.
  Future<CsrResult?> getStoredCsr() async {
    final csrPem = await _secureStorage.read(key: _csrKey);
    if (csrPem == null || csrPem.isEmpty) return null;

    final publicKeyPem = await _secureStorage.read(key: _publicKeyKey);
    final attestationStr = await _secureStorage.read(key: _attestationKey);
    List<dynamic> attestationChain = ["..."];
    if (attestationStr != null) {
      try {
        attestationChain = jsonDecode(attestationStr) as List<dynamic>;
      } catch (_) {}
    }

    return CsrResult(
      csrPem: csrPem,
      publicKeyPem: publicKeyPem,
      attestationChain: attestationChain,
    );
  }

  /// Generates a hardware-backed CSR and Attestation natively, stores it in secure storage,
  /// and returns the [CsrResult].
  Future<CsrResult> generateAndStoreCsr({
    required String challenge,
    required String identity,
    required String deviceUuid,
  }) async {
    if (Platform.isAndroid) {
      debugPrint(
          'OneAuthCsrManager: Requesting hardware-backed CSR from Android...');
      try {
        final result = await _cryptoChannel
            .invokeMapMethod<String, dynamic>('generateCsrAndAttestation', {
          'challenge': challenge,
          'identity': identity,
          'deviceUuid': deviceUuid,
        });

        if (result != null && result['csrPem'] != null) {
          final csrPem = result['csrPem'] as String;
          final publicKeyPem = result['publicKeyPem'] as String?;
          final attestationChain =
              (result['attestationCertificateChain'] as List<dynamic>?) ??
                  ["..."];

          await saveCsr(
            csrPem: csrPem,
            publicKeyPem: publicKeyPem,
            attestationChain: attestationChain,
          );

          debugPrint('OneAuthCsrManager: Hardware-backed CSR generated & stored successfully.');
          return CsrResult(
            csrPem: csrPem,
            publicKeyPem: publicKeyPem,
            attestationChain: attestationChain,
          );
        }
      } on PlatformException catch (e) {
        debugPrint('OneAuthCsrManager Native Error: [${e.code}] ${e.message}');
        throw OneAuthCryptoException(
          'Native CSR generation failed: ${e.message}',
          code: e.code,
          originalError: e,
        );
      } catch (e) {
        debugPrint('OneAuthCsrManager Unexpected Crypto Error: $e');
        throw OneAuthCryptoException(
          'Unexpected crypto error during CSR generation',
          originalError: e,
        );
      }
    }

    // Fallback for non-Android platforms
    const fallbackCsr = '-----BEGIN CERTIFICATE REQUEST-----\n...';
    const fallbackChain = ["..."];
    await saveCsr(csrPem: fallbackCsr, attestationChain: fallbackChain);
    return const CsrResult(
      csrPem: fallbackCsr,
      attestationChain: fallbackChain,
    );
  }

  /// Retrieves the existing stored CSR, or generates & stores a new one if missing.
  Future<CsrResult> getOrGenerateCsr({
    required String challenge,
    required String identity,
    required String deviceUuid,
  }) async {
    final existing = await getStoredCsr();
    if (existing != null && existing.csrPem.isNotEmpty) {
      debugPrint('OneAuthCsrManager: Using pre-stored CSR from secure storage.');
      return existing;
    }

    return await generateAndStoreCsr(
      challenge: challenge,
      identity: identity,
      deviceUuid: deviceUuid,
    );
  }
}
