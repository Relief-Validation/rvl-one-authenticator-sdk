import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// RFC 6238 / RFC 4226 compliant Time-based One-Time Password (TOTP) generator.
///
/// Supports standard HMAC-SHA1 6-digit TOTP calculation over 30-second steps.
/// Allows secret derivation from a device's public key during CSR enrollment,
/// as well as code generation and verification with configurable step skew.
class OneAuthTotpGenerator {
  static const int codeDigits = 6;
  static const int timeStepSeconds = 30;
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static final Random _secureRandom = Random.secure();

  OneAuthTotpGenerator._();

  // ---- Secret generation ----

  /// Generates a random 20-byte (160-bit) Base32 TOTP secret.
  static String generateSecret() {
    final buffer = Uint8List(20);
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = _secureRandom.nextInt(256);
    }
    return _base32Encode(buffer);
  }

  /// Derives a deterministic Base32 secret from raw bytes via SHA-256.
  static String generateSecretFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('bytes cannot be empty');
    }
    final hash = sha256.convert(bytes).bytes;
    return _base32Encode(Uint8List.fromList(hash));
  }

  /// Derives a Base32 TOTP secret from a base64-encoded nonce string.
  static String generateSecretFromNonce(String nonceBase64) {
    if (nonceBase64.trim().isEmpty) {
      throw ArgumentError('nonceBase64 cannot be null or blank');
    }
    final trimmed = nonceBase64.trim();
    try {
      final bytes = base64.decode(trimmed);
      return generateSecretFromBytes(Uint8List.fromList(bytes));
    } catch (_) {
      return generateSecretFromBytes(
        Uint8List.fromList(utf8.encode(trimmed)),
      );
    }
  }

  // ---- Code generation ----

  /// Generates the current TOTP code for the given [secretBase32].
  static String generateCode(String secretBase32, {DateTime? at}) {
    final keyBytes = _base32Decode(secretBase32);
    final time = at ?? DateTime.now().toUtc();
    final counter = time.millisecondsSinceEpoch ~/ (timeStepSeconds * 1000);
    return _generateForCounter(keyBytes, counter);
  }

  static String _generateForCounter(Uint8List keyBytes, int counter) {
    // 8-byte big-endian counter, per RFC 4226.
    final counterBytes = ByteData(8)..setInt64(0, counter, Endian.big);

    // HMAC-SHA1(key, counter)
    final hmac = Hmac(sha1, keyBytes);
    final hash = hmac.convert(counterBytes.buffer.asUint8List()).bytes;

    // Dynamic truncation (RFC 4226 section 5.3).
    final offset = hash[hash.length - 1] & 0x0f;
    final binaryCode = ((hash[offset] & 0x7f) << 24) |
    ((hash[offset + 1] & 0xff) << 16) |
    ((hash[offset + 2] & 0xff) << 8) |
    (hash[offset + 3] & 0xff);

    final otp = binaryCode % pow(10, codeDigits).toInt();
    return otp.toString().padLeft(codeDigits, '0');
  }

  // ---- Verification ----

  /// Validates a submitted TOTP code, allowing ±1 window step (±30s skew).
  static bool verifyCode(String secretBase32, String submittedCode,
      {int windowSteps = 1, DateTime? at}) {
    final cleanCode = submittedCode.replaceAll(RegExp(r'\s'), '').trim();
    if (cleanCode.length != codeDigits) return false;

    final code = int.tryParse(cleanCode);
    if (code == null) return false;

    final keyBytes = _base32Decode(secretBase32);
    final time = at ?? DateTime.now().toUtc();
    final currentCounter = time.millisecondsSinceEpoch ~/ (timeStepSeconds * 1000);

    for (var i = -windowSteps; i <= windowSteps; i++) {
      final expected = _generateForCounter(keyBytes, currentCounter + i);
      if (expected == cleanCode) return true;
    }
    return false;
  }

  /// Seconds remaining until the current code expires.
  static int getSecondsRemaining({DateTime? at}) {
    final now = (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    const stepMs = timeStepSeconds * 1000;
    final nextWindow = ((now ~/ stepMs) + 1) * stepMs;
    return (nextWindow - now) ~/ 1000;
  }

  // ---- Base32 (RFC 4648) ----

  static String _base32Encode(Uint8List data) {
    final result = StringBuffer();
    var buffer = 0, bitsLeft = 0;

    for (final b in data) {
      buffer = (buffer << 8) | (b & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        result.write(_base32Alphabet[(buffer >> bitsLeft) & 0x1f]);
      }
    }

    if (bitsLeft > 0) {
      buffer <<= (5 - bitsLeft);
      result.write(_base32Alphabet[buffer & 0x1f]);
    }

    return result.toString();
  }

  static Uint8List _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll('=', '');
    final output = <int>[];
    var bits = 0, value = 0;
    for (final char in cleaned.split('')) {
      final idx = _base32Alphabet.indexOf(char);
      if (idx == -1) continue;
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return Uint8List.fromList(output);
  }
}