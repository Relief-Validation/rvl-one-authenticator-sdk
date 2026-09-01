import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// RFC 6238 compliant Time-based One-Time Password (TOTP) generator.
///
/// This utility provides the standard HMAC-SHA1 TOTP algorithm.
/// It requires a per-user Base32-encoded secret, which should be stored
/// securely on the device (e.g., using flutter_secure_storage).
class OneAuthTotpGenerator {
  static const int codeDigits = 6;
  static const int timeStepSeconds = 30;

  /// Generates the current TOTP code for the given [secretBase32].
  /// 
  /// The [secretBase32] MUST be a unique, per-user secret established 
  /// during enrollment. Never use public or shared metadata (like package 
  /// names) as a secret.
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

  /// Seconds remaining until the current code expires.
  static int getSecondsRemaining({DateTime? at}) {
    final now = (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    const stepMs = timeStepSeconds * 1000;
    final nextWindow = ((now ~/ stepMs) + 1) * stepMs;
    return (nextWindow - now) ~/ 1000;
  }

  // ---- Base32 (RFC 4648) ----

  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll('=', '');
    final output = <int>[];
    int bits = 0, value = 0;
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
