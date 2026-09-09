import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dio/dio.dart';

import '../one_auth.dart';

abstract class OneAuthInterface {
  Future<void> initialize({
    String? clientSecret,
    String? baseUrl,
    String? bankId,
    FirebaseOptions? firebaseOptions,
    GlobalKey<NavigatorState>? navigatorKey,
  });

  /// Optional global NavigatorKey allowing OneAuth to present Push Approval screens automatically.
  GlobalKey<NavigatorState>? get navigatorKey;

  /// Stream of incoming push notification transaction challenge payloads.
  Stream<Map<String, dynamic>> get onPushChallengeReceived;

  /// Emits a challenge payload to listening UI components.
  void notifyChallengeReceived(Map<String, dynamic> data);

  /// Retrieves the most recent push challenge payload received by the SDK.
  Map<String, dynamic>? get latestPushChallengeData;

  /// Syncs the active FCM token with the backend.
  Future<void> syncFcmToken();

  /// Retrieves and securely stores the active FCM device token.
  Future<String?> getFcmToken();

  /// Retrieves stored FCM token or fetches a fresh one and persists it securely.
  Future<String?> getOrCreateFcmToken();

  /// Retrieves the stored FCM token from secure storage.
  Future<String?> getStoredFcmToken();

  /// Persists certificate, serial, authenticatorUserId, and tokens returned after API success.
  Future<void> persistEnrollmentResult(Map<String, dynamic> responseData);

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

  /// Retrieves the stored CSR PEM.
  Future<String?> getCsrPem();

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
    String? authType,
    String? selectedNumberMatchingCode,
    String? userResponse,
  });

  /// Checks the enrollment status of the device.
  Future<Map<String, dynamic>> checkEnrollmentStatus();

  /// Verifies selected number matching code, push, or biometric setup during enrollment.
  Future<Map<String, dynamic>> verifyNumberMatching({
    String? selectedNumber,
    String? messageId,
    String? preferredAuthenticationType,
    String? userResponse,
  });
}
