import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'crypto_platform.dart';

/// MethodChannel implementation of [OneAuthCryptoPlatform] calling native Kotlin/Swift plugins.
class MethodChannelCryptoPlatform implements OneAuthCryptoPlatform {
  static const MethodChannel _channel = MethodChannel('com.example.one_auth/crypto');

  @override
  Future<String?> getAppSigningHash() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final String? hash = await _channel.invokeMethod<String>('getAppSigningHash');
        if (hash != null && hash.isNotEmpty) {
          debugPrint('MethodChannelCryptoPlatform: Active signing hash -> $hash');
          return hash;
        }
      }
    } on MissingPluginException {
      debugPrint('MethodChannelCryptoPlatform: MethodChannel not available on current platform.');
    } catch (e) {
      debugPrint('MethodChannelCryptoPlatform getAppSigningHash note: $e');
    }
    return null;
  }

  @override
  Future<String?> generateKeyPair(String alias) async {
    try {
      final String? pubKey = await _channel.invokeMethod<String>('generateKeyPair', {'alias': alias});
      return pubKey;
    } on MissingPluginException {
      debugPrint('MethodChannelCryptoPlatform: generateKeyPair missing plugin on current platform.');
      return null;
    } catch (e) {
      debugPrint('MethodChannelCryptoPlatform generateKeyPair error: $e');
      return null;
    }
  }

  @override
  Future<String?> signTransaction(String alias, String payloadHash) async {
    try {
      final String? sig = await _channel.invokeMethod<String>('signTransaction', {
        'alias': alias,
        'payloadHash': payloadHash,
      });
      return sig;
    } on MissingPluginException {
      debugPrint('MethodChannelCryptoPlatform: signTransaction missing plugin on current platform.');
      return null;
    } catch (e) {
      debugPrint('MethodChannelCryptoPlatform signTransaction error: $e');
      return null;
    }
  }

  @override
  Future<bool> verifySignature(String alias, String payloadHash, String signature) async {
    try {
      final bool? isValid = await _channel.invokeMethod<bool>('verifySignature', {
        'alias': alias,
        'payloadHash': payloadHash,
        'signature': signature,
      });
      return isValid ?? false;
    } on MissingPluginException {
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<String?> getPublicKey(String alias) async {
    try {
      final String? pubKey = await _channel.invokeMethod<String>('getPublicKey', {'alias': alias});
      return pubKey;
    } on MissingPluginException {
      return null;
    } catch (e) {
      return null;
    }
  }
}
