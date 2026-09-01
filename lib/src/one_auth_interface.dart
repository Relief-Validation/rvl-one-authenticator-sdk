import 'package:dio/dio.dart';

import '../one_auth.dart';

abstract class OneAuthInterface {
  Future<void> initialize({
    String? clientSecret,
    String? baseUrl,
    String? bankId,
  });

  /// Fetches an enrollment nonce for the current user.
  Future<Map<String, dynamic>> getEnrollmentNonce([String? userId]);

  /// Orchestrates the full enrollment flow.
  Future<Map<String, dynamic>> enroll(OneAuthUser user);

  /// Submits the CSR with attestation and customer info.
  Future<Map<String, dynamic>> submitCsr(OneAuthUser user, {String? sessionToken, String? nonceBase64});

  /// The authenticated Dio client that automatically includes Authorization tokens.
  Dio get dio;

  /// Sets the TOTP secret for the current session/user.
  Future<void> setTotpSecret(String userId, String secret);

  /// Retrieves the TOTP secret.
  Future<String?> getTotpSecret(String userId);

  /// Retrieves the issued certificate PEM.
  Future<String?> getCertificate();

  /// Sets the user-level authentication token.
  void setUserToken(String? token);

  /// Sets the authenticator user ID to be included in all requests.
  void setAuthenticatorUserId(String? id);

  /// Stream to listen for client authentication status changes.
  Stream<bool> get onClientStatusChanged;

  /// Submits a transaction signature.
  Future<Map<String, dynamic>> submitTransactionSignature({
    required String txnId,
    required String txnHash,
    required String pin,
    String? selectedNumberMatchingCode,
  });

  /// Checks the enrollment status of the device.
  Future<Map<String, dynamic>> checkEnrollmentStatus();
}
