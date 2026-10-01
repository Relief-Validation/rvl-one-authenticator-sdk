import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';

/// Minimal equivalent of TransactionChallengeRequest.
class TransactionChallengeRequest {
  final Decimal amount;
  final String bankTxnId;
  final String? customerUniqueKey;
  final String currency;
  final String fromAccount;
  final String toAccount;
  final DateTime? txnTimestamp; // currently excluded from the canonical payload

  TransactionChallengeRequest({
    required dynamic amount,
    required this.bankTxnId,
    this.customerUniqueKey,
    required this.currency,
    required this.fromAccount,
    required this.toAccount,
    this.txnTimestamp,
  }) : amount = amount is Decimal ? amount : Decimal.parse(amount.toString());
}

/// Canonical form: fixed, ASCII, minified, key-sorted JSON string, e.g.
/// {"amount":"10000.00","bankTxnId":"TXN12345","currency":"BDT","fromAccount":"123456789","toAccount":"987654321"}
///
/// Must produce byte-for-byte the same output as the Java backend.
class TransactionHashService {
  /// Keys are appended in alphabetical order (mechanical, unambiguous rule).
  String canonicalPayload(TransactionChallengeRequest t) {
    final fields = <MapEntry<String, String>>[
      MapEntry('amount', _formatAmount(t)),
      MapEntry('bankTxnId', t.bankTxnId),
      MapEntry('currency', t.currency),
      if (t.customerUniqueKey != null && t.customerUniqueKey!.isNotEmpty)
        MapEntry('customerUniqueKey', t.customerUniqueKey!),
      MapEntry('fromAccount', t.fromAccount),
      MapEntry('toAccount', t.toAccount),
      // MapEntry('txnTimestamp', t.txnTimestamp!.toIso8601String()),
    ];

    final sb = StringBuffer('{');
    sb.writeAll(
      fields.map((e) => '"${e.key}":"${_escape(e.value)}"'),
      ',',
    );
    sb.write('}');
    return sb.toString();
  }

  Uint8List canonicalBytes(TransactionChallengeRequest t) {
    // allowInvalid: true replaces non-ASCII chars with '?', matching
    // Java's getBytes(StandardCharsets.US_ASCII) behavior.
    return Uint8List.fromList(
      const AsciiCodec(allowInvalid: true).encode(canonicalPayload(t)),
    );
  }

  /// Lowercase hex SHA-256 of the canonical bytes.
  String sha256Hex(TransactionChallengeRequest t) {
    return sha256.convert(canonicalBytes(t)).toString();
  }

  /// Fixed 2-decimal string, HALF_UP rounding (ties away from zero).
  static String _formatAmount(TransactionChallengeRequest t) {
    return t.amount.round(scale: 2).toStringAsFixed(2);
  }

  static String _escape(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
