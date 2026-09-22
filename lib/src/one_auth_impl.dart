import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart' as pkg;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'one_auth_interface.dart';
import 'core/utils.dart';
import 'models/user.dart';
import 'api/dio_client.dart';
import 'core/env.dart';
import 'core/exceptions.dart';
import 'core/csr_manager.dart';
import 'core/push_manager.dart';
import 'core/secure_id_manager.dart';
import 'core/security_service.dart';
import 'screens/pin_verification_screen.dart';
import 'screens/push_setup_screen.dart';
import 'screens/push_verification_screen.dart';
import 'screens/biometric_verification_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/status_screen.dart';
import 'screens/verification_model_screen.dart';
import 'widgets/snack_bar.dart';
import 'package:freerasp/freerasp.dart';

class OneAuth implements OneAuthInterface {
  static final OneAuth _instance = OneAuth._internal();

  factory OneAuth() => _instance;

  OneAuth._internal();

  static const _cryptoChannel = MethodChannel('com.example.one_auth/crypto');

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final OneAuthCsrManager _csrManager = OneAuthCsrManager(secureStorage: _secureStorage);
  String? _clientSecret;
  String? _baseUrl;
  // String? _bankId;
  String? _clientToken;
  String? _userToken;
  String? _sessionToken;
  String? _nonceBase64;
  String? _authenticatorUserId;
  Map<String, dynamic>? _pendingEnrollmentData;
  late DioClient _dioClient;
  final OneAuthPushManager _pushManager = OneAuthPushManager();
  GlobalKey<NavigatorState>? _navigatorKey;

  bool _isInitialized = false;
  bool _isFreeRASPStarted = false;
  DateTime? _lastSecurityCheck;

  final StreamController<bool> _clientStatusController =
      StreamController<bool>.broadcast();

  @override
  Dio get dio => _dioClient.dio;

  @override
  GlobalKey<NavigatorState>? get navigatorKey => _navigatorKey;

  @override
  Stream<Map<String, dynamic>> get onPushChallengeReceived =>
      _pushManager.onPushChallengeReceived;

  @override
  void notifyChallengeReceived(Map<String, dynamic> data) =>
      _pushManager.notifyChallengeReceived(data);

  @override
  Map<String, dynamic>? get latestPushChallengeData =>
      _pushManager.latestChallengeData;

  @override
  Future<void> syncFcmToken() => _pushManager.syncFcmToken(_dioClient);

  @override
  Future<String?> getFcmToken() => _pushManager.getFcmToken();

  @override
  Future<String?> getOrCreateFcmToken() => _pushManager.getFcmToken();

  @override
  Future<String?> getStoredFcmToken() => _pushManager.getStoredFcmToken();

  @override
  void setUserToken(String? token) {
    _userToken = token;
    debugPrint('OneAuth: User Token updated.');
    if (token != null && token.isNotEmpty && _isInitialized) {
      syncFcmToken();
    }
  }

  @override
  void setAuthenticatorUserId(String? id) async {
    if (id == null || id.isEmpty) return;

    // Check if we already have a valid persistent ID
    final existingId = await _secureStorage.read(key: 'authenticatorUserId');
    if (existingId != null && existingId.isNotEmpty) {
      _authenticatorUserId = existingId;
      debugPrint('OneAuth: Using existing persistent ID: $existingId');
      return;
    }

    _authenticatorUserId = id;
    await _secureStorage.write(key: 'authenticatorUserId', value: id);

    debugPrint('OneAuth: ID Initialized - $id');
  }

  Future<String?> _getOrCreateAuthenticatorId([String? providedId]) async {
    if (_authenticatorUserId != null && providedId == null) return _authenticatorUserId;

    String? id = await _secureStorage.read(key: 'authenticatorUserId');

    if (id == null || id.isEmpty) {
      if (providedId != null && providedId.isNotEmpty) {
        id = providedId;

        _authenticatorUserId = id;
        await _secureStorage.write(key: 'authenticatorUserId', value: id);
        debugPrint('OneAuth: Created persistent ID from provided input: $id');
      } else {
        debugPrint('OneAuth: No ID provided and none found in storage.');
      }
    } else {
      _authenticatorUserId = id;
    }

    return id;
  }

  @override
  Stream<bool> get onClientStatusChanged => _clientStatusController.stream;

  @override
  Future<void> initialize({
    String? clientSecret,
    String? baseUrl,
    String? bankId,
    FirebaseOptions? firebaseOptions,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    if (_isInitialized) {
      debugPrint('OneAuth: SDK already initialized.');
      return;
    }
    debugPrint('OneAuth: Initializing Client SDK...');

    _navigatorKey = navigatorKey;
    _clientSecret = clientSecret;
    _baseUrl = baseUrl ?? Env.baseUrl;
    // _bankId = bankId ?? Env.bankId;

    // Load or Generate the persistent Authenticator User ID once
    await _getOrCreateAuthenticatorId();

    debugPrint('OneAuth: Base URL set to $_baseUrl');
    // debugPrint('OneAuth: Bank ID set to $_bankId');
    debugPrint('OneAuth: Authenticator User ID: $_authenticatorUserId');

    _dioClient = DioClient(
      baseUrl: _baseUrl!,
      getClientToken: () async => _clientToken,
      getUserToken: () async => _userToken,
      getAuthenticatorUserId: () async => _authenticatorUserId,
      onSecurityCheck: _ensureSecurity,
      onRefreshToken: _refreshToken,
      onSessionExpired: _handleSessionExpired,
    );

    // Initialize freeRASP for security monitoring
    await _ensureSecurity();

    await _authenticateClient();

    // Initialize FCM Push Manager internally
    await _pushManager.initialize(
      dioClient: _dioClient,
      firebaseOptions: firebaseOptions,
    );

    // Listen for incoming Push Challenges and auto-navigate if navigatorKey is set
    _pushManager.onPushChallengeReceived.listen((data) {
      _handleAutoNavigationForPushChallenge(data);
    });

    _isInitialized = true;
    debugPrint('OneAuth: SDK Initialization Complete.');
  }

  void _handleAutoNavigationForPushChallenge(Map<String, dynamic> data) {
    if (_navigatorKey?.currentState == null) return;

    final txnId = data['txnId'];
    final txnHash = data['txnHash'];
    final authType = data['authType'] ?? 'PUSH';

    if (txnId == null || txnHash == null) return;

    debugPrint('OneAuth: Auto-navigating to push challenge verification screen...');

    if (authType == 'PUSH') {
      _navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (_) => OneAuthPushSetupScreen(
            type: data['numberMatchingCode'] != null
                ? PushSetupType.matching
                : PushSetupType.approval,
            user: OneAuthUser(id: _authenticatorUserId ?? '', name: '', email: ''),
            onComplete: () {
              _navigatorKey?.currentState?.pop();
            },
          ),
        ),
      );
    } else if (authType == 'BIOMETRIC') {
      _navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (_) => OneAuthBiometricVerificationScreen(
            txnId: txnId,
            txnHash: txnHash,
            onComplete: () {
              _navigatorKey?.currentState?.pop();
            },
          ),
        ),
      );
    } else {
      _navigatorKey!.currentState!.push(
        MaterialPageRoute(
          builder: (_) => OneAuthPinVerificationScreen(
            txnId: txnId,
            txnHash: txnHash,
            numberMatchingCode: formatNumberMatchingCode(data['numberMatchingCode'] ?? data['number_matching_code']),
            pinLength: authType == 'TOTP' ? 6 : 4,
            onComplete: () {
              _navigatorKey?.currentState?.pop();
            },
          ),
        ),
      );
    }
  }

  void _handleSessionExpired() {
    debugPrint('OneAuth: Handling session expiration (401)...');
    _clientToken = null;
    _userToken = null;
    _sessionToken = null;
    _clientStatusController.add(false);

    // We could potentially trigger a re-authentication of the client here
    // but usually, it's safer to let the next request trigger it or let the app handle it.
  }

  Future<bool> _refreshToken() async {
    debugPrint('OneAuth: Attempting silent token refresh...');
    try {
      await _authenticateClient();
      return true;
    } catch (e) {
      debugPrint('OneAuth: Silent refresh failed: $e');
      return false;
    }
  }

  Future<void> _ensureSecurity() async {
    // 1. Cooldown check: prevent slamming the system with integrity requests.
    // Reading system properties and settings is expensive and triggers Logcat warnings on some devices.
    if (_lastSecurityCheck != null &&
        DateTime.now().difference(_lastSecurityCheck!) < const Duration(seconds: 10)) {
      return;
    }

    // 2. Initialize freeRASP only once.
    await _initFreeRASP();

    // 3. Check if it is running
    if (!_isFreeRASPStarted) {
      debugPrint('OneAuth: Security monitoring blocked or failed to start. Opening Settings...');
      await openAppSettings();

      throw OneAuthSecurityException(
        'Security monitoring is required for this application. '
        'Please ensure "read the list of installed apps" (or similar device integrity permission) '
        'is allowed in your App Settings.',
      );
    }

    // 4. Perform the actual integrity validation using the existing listener state
    final integrity = await getDeviceIntegrity();
    _validateIntegrity(integrity, 'SDK Operation');

    _lastSecurityCheck = DateTime.now();
  }

  Future<void> _initFreeRASP({bool force = false}) async {
    if (_isFreeRASPStarted && !force) return;

    try {
      final packageInfo = await pkg.PackageInfo.fromPlatform();
      final appPackageId = packageInfo.packageName;

      await SecurityService().initialize(
        packageName: appPackageId,
        androidSigningHashes: [], // SecurityService auto-detects current active signing hash at runtime
        watcherMail: 'security@dginfotech.com',
      );

      _isFreeRASPStarted = SecurityService().isInitialized;
      debugPrint('OneAuth: freeRASP Security Monitoring Started/Verified via SecurityService.');
    } catch (e) {
      _isFreeRASPStarted = false;
      debugPrint('OneAuth: Failed to start/verify freeRASP: $e');
    }
  }

  Future<void> _authenticateClient() async {
    try {
      final packageInfo = await pkg.PackageInfo.fromPlatform();
      final appPackageId = packageInfo.packageName;

      final response = await _dioClient.dio.post(
        '/auth/client/token',
        data: {
          'clientSecret': _clientSecret,
          'appPackageId': appPackageId,
        },
      );


      _clientToken = response.data['token'] ??
          response.data['data']?['token'] ??
          response.data['access_token'] ??
          response.data['accessToken'];
      _clientStatusController.add(true);
      debugPrint(
          'OneAuth: Client Login Successful. Token: ${_clientToken?.substring(0, 10)}...');
    } on DioException catch (e) {
      _clientStatusController.add(false);
      debugPrint('OneAuth: Client Login Failed: ${e.message}');
      throw OneAuthAuthException(
        e.message ?? 'Client Authentication Failed',
        e,
      );
    }
  }

  @override
  Future<void> setTotpSecret(String userId, String secret) async {
    _ensureInitialized();
    await _secureStorage.write(key: 'totp_secret_$userId', value: secret);
  }

  @override
  Future<String?> getTotpSecret(String userId) async {
    _ensureInitialized();
    return await _secureStorage.read(key: 'totp_secret_$userId');
  }

  @override
  Future<String?> getCertificate() async {
    _ensureInitialized();
    return await _secureStorage.read(key: 'issued_certificate');
  }

  @override
  Future<String?> getCsrPem() async {
    _ensureInitialized();
    return await _csrManager.getCsrPem();
  }

  @override
  Future<Map<String, dynamic>> getEnrollmentNonce([String? userId]) async {
    _ensureInitialized();

    // If a userId is provided, ensure it's persisted as the authenticator ID
    if (userId != null && userId.isNotEmpty) {
      await _getOrCreateAuthenticatorId(userId);
    }

    debugPrint('OneAuth: Fetching enrollment nonce for $_authenticatorUserId...');
    try {
      final response = await _dioClient.dio.post(
        '/enrollment/nonce',
        data: {
          'bankId': _authenticatorUserId,
        },
      );

      final data = response.data;
      _sessionToken = data['sessionToken'] ??
          data['data']?['sessionToken'] ??
          data['session_token'];
      _nonceBase64 = data['nonceBase64'] ??
          data['data']?['nonceBase64'] ??
          data['nonce_base64'];

      debugPrint(
          'OneAuth: Enrollment nonce fetched. SessionToken: ${_sessionToken?.substring(0, 5)}...');

      return response.data;
    } on DioException catch (e) {
      debugPrint('OneAuth: Failed to fetch enrollment nonce: ${e.message}');
      throw OneAuthNetworkException(
        e.message ?? 'Failed to fetch enrollment nonce',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> enroll(OneAuthUser user) async {
    _ensureInitialized();
    debugPrint('OneAuth: Starting Enrollment Orchestration...');

    final integrity = await getDeviceIntegrity();
    _validateIntegrity(integrity, 'Enrollment');

    // Step 1: Explicitly fetch a fresh nonce and session
    final nonceData = await getEnrollmentNonce(user.id);
    final freshSessionToken = nonceData['sessionToken'] ?? nonceData['data']?['sessionToken'] ?? nonceData['session_token'];
    final freshNonce = nonceData['nonceBase64'] ?? nonceData['data']?['nonceBase64'] ?? nonceData['nonce_base64'];

    if (freshSessionToken == null || freshNonce == null) {
      throw OneAuthSessionException('Failed to obtain fresh enrollment session');
    }

    // Step 2-4: Pass the fresh data explicitly to submitCsr
    return await submitCsr(user, sessionToken: freshSessionToken, nonceBase64: freshNonce);
  }

  @override
  Future<Map<String, dynamic>> submitCsr(OneAuthUser user, {String? sessionToken, String? nonceBase64}) async {
    debugPrint('OneAuth: Building and submitting CSR...');

    final integrity = await getDeviceIntegrity();
    _validateIntegrity(integrity, 'CSR submission');

    // Use provided fresh tokens, fall back to instance variables, or fetch a fresh enrollment nonce if missing
    String? effectiveSessionToken = sessionToken ?? _sessionToken;
    String? effectiveNonce = nonceBase64 ?? _nonceBase64;

    if (effectiveSessionToken == null ||
        effectiveNonce == null ||
        effectiveSessionToken.isEmpty ||
        effectiveNonce.isEmpty) {
      debugPrint('OneAuth: Session token or nonce missing. Fetching fresh enrollment nonce...');
      final nonceData = await getEnrollmentNonce(user.id);
      effectiveSessionToken = nonceData['sessionToken'] ??
          nonceData['data']?['sessionToken'] ??
          nonceData['session_token'];
      effectiveNonce = nonceData['nonceBase64'] ??
          nonceData['data']?['nonceBase64'] ??
          nonceData['nonce_base64'];
    }

    if (effectiveSessionToken == null ||
        effectiveNonce == null ||
        effectiveSessionToken.isEmpty ||
        effectiveNonce.isEmpty) {
      throw OneAuthSessionException(
        'No active enrollment session found. Failed to obtain fresh enrollment nonce.',
      );
    }

    try {
      // Ensure we have a persistent formatted ID (Generated if missing)
      final authenticatorUserId = await _getOrCreateAuthenticatorId(user.id);
      final deviceUuid = await OneAuthSecureIdManager.getOrCreateDeviceUuid();
      final appInstanceId = await OneAuthSecureIdManager.getOrCreateAppInstanceId();

      // Validation: Ensure DOB is in YYYY-MM-DD format
      if (user.dob != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(user.dob!)) {
        debugPrint('OneAuth Warning: DOB "${user.dob}" might not match server format YYYY-MM-DD');
      }

      String osVersion = 'Unknown';
      String deviceName = 'Unknown';
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        osVersion =
            'Android ${androidInfo.version.release} / API ${androidInfo.version.sdkInt}';
        final manufacturer = androidInfo.manufacturer;
        final model = androidInfo.model;
        deviceName = model.toLowerCase().startsWith(manufacturer.toLowerCase())
            ? model
            : '$manufacturer $model';
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        osVersion = 'iOS ${iosInfo.systemVersion}';
        deviceName = iosInfo.name.isNotEmpty ? iosInfo.name : iosInfo.model;
      }

      final csrResult = await _csrManager.generateCsr(
        challenge: effectiveNonce,
        identity: authenticatorUserId ?? '',
        deviceUuid: deviceUuid,
      );

      final payload = <String, dynamic>{
        "sessionToken": effectiveSessionToken,
        "customerUniqueKey": authenticatorUserId,
        "deviceUuid": deviceUuid,
        "csrPem": csrResult.csrPem,
        "attestationCertificateChain": csrResult.attestationChain,
        "accountNumber": user.accountNumber,
        "customerName": user.name,
        "nid": user.nid,
        "dob": user.dob,
        "mobile": user.phoneNumber,
        "email": user.email,
        "appInstanceId": appInstanceId,
        "osVersion": osVersion,
        "deviceName": deviceName,
        "preferredAuthenticationType": user.preferredAuthenticationType,
      };

      if (user.preferredAuthenticationType == 'TOTP') {
        payload["totpCode"] = user.totpCode ?? user.pin;
      }
      if (user.preferredAuthenticationType == 'PIN') {
        payload["pinCode"] = user.pin;
      }
      if (user.preferredAuthenticationType == 'NUMBER_MATCHING' ||
          user.preferredAuthenticationType == 'PUSH') {
        final fcmToken = await getOrCreateFcmToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          payload["fcmToken"] = fcmToken;
        }
      }

      developer.log('OCSR with payload: $payload', name: 'OneAuth');
      // Log if any value is null
      payload.forEach((key, value) {
        if (value == null) {
          debugPrint('OneAuth Warning: Payload field "$key" is NULL');
        }
      });

      final response = await _dioClient.dio.post(
        '/enrollment/csr',
        data: payload,
      );

      developer.log('submitCsr response: ${response.data}', name: 'OneAuth');

      // Clear session after use to ensure freshness on next attempt
      _sessionToken = null;
      _nonceBase64 = null;

      final data = response.data is Map<String, dynamic> ? response.data : <String, dynamic>{};
      if (effectiveSessionToken.isNotEmpty) {
        data['sessionToken'] ??= effectiveSessionToken;
      }
      await _secureStorage.write(key: 'device_uuid', value: deviceUuid);

      final authType = user.preferredAuthenticationType?.toUpperCase();
      if (authType == 'TOTP' || authType == 'PIN' || authType == 'BIOMETRIC') {
        await persistEnrollmentResult(data);
        debugPrint('OneAuth: CSR submitted and enrollment persisted for $authType.');
      } else {
        _pendingEnrollmentData = data;
        try {
          await _secureStorage.write(
            key: 'pending_enrollment_data',
            value: jsonEncode(data),
          );
        } catch (e) {
          debugPrint('OneAuth Warning: Failed to save pending_enrollment_data: $e');
        }
        debugPrint('OneAuth: CSR submitted for $authType. Persistence deferred until verification success.');
      }

      return data;
    } on DioException catch (e) {
      debugPrint('OneAuth: CSR Submission Failed: ${e.message}');
      throw OneAuthNetworkException(
        e.message ?? 'CSR Submission Failed',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  @override
  Future<void> persistEnrollmentResult(Map<String, dynamic> responseData) async {
    final data = responseData['data'] is Map<String, dynamic>
        ? responseData['data'] as Map<String, dynamic>
        : responseData;

    final issuedCert = data['certificatePem'] ?? data['certificate_pem'];
    final certificateSerial = data['certificateSerial'] ?? data['certificate_serial'];
    final serverCustomerId = data['authenticatorUserId'] ?? data['authenticator_user_id'];
    final fcmToken = data['fcmToken'] ?? data['fcm_token'];
    final deviceUuid = data['deviceUuid'] ?? data['device_uuid'];

    if (issuedCert != null && issuedCert.toString().isNotEmpty) {
      await _secureStorage.write(key: 'issued_certificate', value: issuedCert.toString());
      debugPrint('OneAuth: Saved issued_certificate to secure storage.');
    }

    if (certificateSerial != null) {
      await _secureStorage.write(key: 'certificate_serial', value: certificateSerial.toString());
      debugPrint('OneAuth: Saved certificate_serial to secure storage.');
    }

    if (serverCustomerId != null && serverCustomerId.toString().isNotEmpty) {
      _authenticatorUserId = serverCustomerId.toString();
      await _secureStorage.write(key: 'authenticatorUserId', value: serverCustomerId.toString());
      debugPrint('OneAuth: Saved authenticatorUserId ($serverCustomerId) to secure storage.');
    }

    if (fcmToken != null && fcmToken.toString().isNotEmpty) {
      await _secureStorage.write(key: 'fcm_token', value: fcmToken.toString());
      debugPrint('OneAuth: Saved fcm_token to secure storage.');
    }

    if (deviceUuid != null && deviceUuid.toString().isNotEmpty) {
      await _secureStorage.write(key: 'device_uuid', value: deviceUuid.toString());
      debugPrint('OneAuth: Saved device_uuid to secure storage.');
    }
  }

  @override
  Future<Map<String, dynamic>> getDeviceIntegrity() async {
    final secState = SecurityService().state;
    return {
      "rootedOrJailbroken": secState.isRooted,
      "emulatorDetected": secState.isEmulator,
      "appTamperDetected": secState.isTampered,
      "hookDetected": secState.isHooked,
      "deviceUntrusted": secState.isUntrusted,
      "vpnActive": secState.isVpnActive,
      "scanActive": SecurityService().isInitialized,
      "attestationToken": null,
    };
  }

  void _validateIntegrity(Map<String, dynamic> integrity, String operation) {
    debugPrint('OneAuth: Validating Device Integrity for $operation...');
    debugPrint('OneAuth: Integrity State: $integrity');

    final List<String> threats = [];

    if (integrity["rootedOrJailbroken"] == true) threats.add('Rooted/Jailbroken');
    if (integrity["emulatorDetected"] == true) threats.add('Emulator');
    if (integrity["appTamperDetected"] == true) threats.add('App Tampering');
    if (integrity["hookDetected"] == true) threats.add('Hooking/Instrumentation');

    if (integrity["deviceUntrusted"] == true) {
      // In development, this is often triggered because the IDE/Debugger is attached.
      if (kDebugMode) {
        debugPrint('OneAuth Warning: Untrusted Environment detected but ignored in kDebugMode.');
      } else {
        threats.add('Untrusted Environment (Debug/Unofficial Store)');
      }
    }

    if (integrity["vpnActive"] == true) threats.add('VPN Active');

    if (threats.isNotEmpty) {
      final message = '$operation blocked due to security threats: ${threats.join(", ")}';
      debugPrint('OneAuth Security Violation: $message');
      throw OneAuthSecurityException(message);
    }

    debugPrint('OneAuth: Device Integrity Validation Passed.');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw OneAuthValidationException(
        'OneAuth SDK is not initialized. Please call initialize() and wait for it to complete.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> submitTransactionSignature({
    required String txnId,
    required String txnHash,
    required String pin,
    String? authType,
    String? selectedNumberMatchingCode,
    String? userResponse,
  }) async {
    _ensureInitialized();

    // Always ensure security before signing
    await _ensureSecurity();

    debugPrint('OneAuth: Signing and submitting transaction $txnId...');

    // Initial check before starting the signing process
    final initialIntegrity = await getDeviceIntegrity();
    _validateIntegrity(initialIntegrity, 'Transaction signing');

    var deviceUuid = await _secureStorage.read(key: 'device_uuid');
    var certificateSerial = await _secureStorage.read(key: 'certificate_serial');

    if (deviceUuid == null || certificateSerial == null) {
      if (_pendingEnrollmentData != null) {
        await persistEnrollmentResult(_pendingEnrollmentData!);
        deviceUuid = await _secureStorage.read(key: 'device_uuid');
        certificateSerial = await _secureStorage.read(key: 'certificate_serial');
      } else {
        final pendingJson = await _secureStorage.read(key: 'pending_enrollment_data');
        if (pendingJson != null && pendingJson.isNotEmpty) {
          try {
            final pendingData = jsonDecode(pendingJson) as Map<String, dynamic>;
            await persistEnrollmentResult(pendingData);
            deviceUuid = await _secureStorage.read(key: 'device_uuid');
            certificateSerial = await _secureStorage.read(key: 'certificate_serial');
          } catch (e) {
            debugPrint('OneAuth Warning: Failed to recover pending enrollment data: $e');
          }
        }
      }
    }

    if (deviceUuid == null || certificateSerial == null) {
      throw OneAuthValidationException('Device not enrolled. Please enroll first.');
    }

    String? signatureBase64;

    if (Platform.isAndroid) {
      try {
        final result = await _cryptoChannel.invokeMethod<String>('signTransactionHash', txnHash);
        if (result != null) {
          signatureBase64 = result;
        }
      } on PlatformException catch (e) {
        debugPrint('OneAuth Native Signing Error: [${e.code}] ${e.message}');
        debugPrint('OneAuth Native Signing Details: ${e.details}');
        throw OneAuthCryptoException(
          'Native signing failed: ${e.message}',
          code: e.code,
          originalError: e,
        );
      } catch (e) {
        debugPrint('OneAuth Unexpected Native Signing Error: $e');
        throw OneAuthCryptoException(
          'Unexpected error during native signing',
          originalError: e,
        );
      }
    }

    if (signatureBase64 == null) {
      throw OneAuthCryptoException('Signature generation not supported or failed on this platform');
    }

    // Final check right before making the network request
    final finalIntegrity = await getDeviceIntegrity();
    _validateIntegrity(finalIntegrity, 'Transaction submission');

    final payload = <String, dynamic>{
      "deviceUuid": deviceUuid,
      "certificateSerial": certificateSerial,
      "txnHash": txnHash,
      "signatureBase64": signatureBase64,
      "deviceIntegrity": finalIntegrity,
    };

    if (authType == 'TOTP' || (authType == null && pin.length == 6)) {
      payload["totpCode"] = pin;
    }
    if (authType == 'PIN' || (authType == null && pin.length == 4)) {
      payload["pinCode"] = pin;
    }
    if (authType == 'NUMBER_MATCHING') {
      payload["numberMatchingCode"] = pin;
    }
    if (userResponse != null && userResponse.isNotEmpty) {
      payload["userResponse"] = userResponse;
    } else if (authType == 'PUSH' || authType == 'BIOMETRIC') {
      payload["userResponse"] = 'true';
    }

    developer.log('submitTransactionSignature request: $payload', name: 'OneAuth');

    try {
      final response = await _dioClient.dio.post(
        '/transactions/$txnId/signature',
        data: payload,
      );
      developer.log('submitTransactionSignature response: ${response.data}', name: 'OneAuth');

      final data = response.data;
      final responseMap = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
      final statusStr = (userResponse == 'false' || (data != null && data['status'] == 'DECLINED'))
          ? 'DECLINED'
          : 'VERIFIED';

      _pushManager.notifyChallengeReceived({
        'status': statusStr,
        'txnId': txnId,
        'authType': authType,
        ...responseMap,
      });

      if (data != null && data['status'] == 'DECLINED') {
        final reason = data['reason'] ?? 'Transaction Declined';
        debugPrint('OneAuth: Transaction signature declined: $reason');
        throw OneAuthValidationException(reason);
      }

      debugPrint('OneAuth: Transaction signature submitted successfully.');
      return data;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      String? errorMessage;
      if (responseData is Map) {
        errorMessage = responseData['reason'] ?? responseData['message'];
      }
      errorMessage ??= e.message;

      debugPrint('OneAuth: Transaction signature failed: $errorMessage');
      throw OneAuthNetworkException(
        errorMessage ?? 'Transaction signature failed',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> checkEnrollmentStatus() async {
    _ensureInitialized();
    final certificateSerial = await _secureStorage.read(key: 'certificate_serial');

    if (certificateSerial == null) {
      debugPrint('OneAuth: No certificate serial found locally.');
      return {'valid': false, 'reason': 'CERTIFICATE_NOT_FOUND'};
    }

    debugPrint('OneAuth: Checking enrollment status for serial: $certificateSerial');

    try {
      final response = await _dioClient.dio.get(
        '/enrollment/status',
        queryParameters: {
          'certificateSerial': certificateSerial,
        },
      );

      final data = response.data;
      debugPrint('OneAuth: Enrollment status check result: $data');
      return data;
    } on DioException catch (e) {
      debugPrint('OneAuth: Failed to check enrollment status: ${e.message}');

      // If it's a 404, we can treat it as not found
      if (e.response?.statusCode == 404) {
        return {'valid': false, 'reason': 'CERTIFICATE_NOT_FOUND'};
      }

      throw OneAuthNetworkException(
        e.message ?? 'Failed to check enrollment status',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> verifyNumberMatching({
    String? selectedNumber,
    String? messageId,
    String? preferredAuthenticationType,
    String? userResponse,
    String? sessionToken,
  }) async {
    _ensureInitialized();

    final effectiveSessionToken = sessionToken ??
        _sessionToken ??
        _pendingEnrollmentData?['sessionToken'] ??
        _pendingEnrollmentData?['data']?['sessionToken'] ??
        _pendingEnrollmentData?['session_token'];

    String? resolvedToken = effectiveSessionToken;
    if (resolvedToken == null || resolvedToken.isEmpty) {
      final pendingJson = await _secureStorage.read(key: 'pending_enrollment_data');
      if (pendingJson != null && pendingJson.isNotEmpty) {
        try {
          final pendingData = jsonDecode(pendingJson) as Map<String, dynamic>;
          resolvedToken = pendingData['sessionToken'] ??
              pendingData['data']?['sessionToken'] ??
              pendingData['session_token'];
        } catch (e) {
          debugPrint('OneAuth Warning: Failed to parse pending_enrollment_data: $e');
        }
      }
    }

    final deviceUuid = await OneAuthSecureIdManager.getOrCreateDeviceUuid();
    final fcmToken = await getFcmToken();

    final authType = preferredAuthenticationType ?? 'NUMBER_MATCHING';

    final payload = <String, dynamic>{
      "messageId": messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      "deviceUuid": deviceUuid,
      "fcmToken": fcmToken,
      "preferredAuthenticationType": authType,
    };

    if (resolvedToken != null && resolvedToken.isNotEmpty) {
      payload["sessionToken"] = resolvedToken;
    }

    if (selectedNumber != null && selectedNumber.isNotEmpty) {
      payload["number"] = selectedNumber;
    }

    if (userResponse != null && userResponse.isNotEmpty) {
      payload["userResponse"] = userResponse;
    } else if (authType == 'PUSH' || authType == 'BIOMETRIC') {
      payload["userResponse"] = 'true';
    }

    debugPrint('OneAuth: Calling /verify with payload: $payload');

    try {
      final response = await _dioClient.dio.post(
        '/enrollment/verify',
        data: payload,
      );

      debugPrint('OneAuth: /verify response: ${response.data}');

      // Retrieve pending CSR enrollment data if available
      Map<String, dynamic> pendingData = {};
      if (_pendingEnrollmentData != null) {
        pendingData = _pendingEnrollmentData!;
      } else {
        final pendingJson = await _secureStorage.read(key: 'pending_enrollment_data');
        if (pendingJson != null && pendingJson.isNotEmpty) {
          try {
            pendingData = jsonDecode(pendingJson) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('OneAuth Warning: Failed to parse pending_enrollment_data: $e');
          }
        }
      }

      final responseData = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};

      final dataToPersist = <String, dynamic>{
        ...pendingData,
        ...responseData,
      };

      await persistEnrollmentResult(dataToPersist);
      _pendingEnrollmentData = null;
      await _secureStorage.delete(key: 'pending_enrollment_data');

      final statusStr = (userResponse == 'false') ? 'DECLINED' : 'VERIFIED';
      _pushManager.notifyChallengeReceived({
        'status': statusStr,
        'messageId': messageId,
        'preferredAuthenticationType': authType,
        ...dataToPersist,
      });

      return dataToPersist;
    } on DioException catch (e) {
      debugPrint('OneAuth: /verify failed: ${e.message}');
      throw OneAuthNetworkException(
        e.message ?? 'Number matching verification failed',
        statusCode: e.response?.statusCode,
        originalError: e,
      );
    }
  }

  @override
  Future<bool?> verifyTransaction(
    BuildContext context, {
    required String txnId,
    required String txnHash,
    required String authType,
  }) async {
    final navigator = Navigator.of(context);

    if (authType == 'PIN' || authType == 'TOTP') {
      return navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => OneAuthPinVerificationScreen(
            txnId: txnId,
            txnHash: txnHash,
            pinLength: authType == 'TOTP' ? 6 : 4,
            onComplete: () => navigator.pop(true),
          ),
        ),
      );
    } else if (authType == 'NUMBER_MATCHING' || authType == 'PUSH') {
      return navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => OneAuthPushVerificationScreen(
            txnId: txnId,
            txnHash: txnHash,
            authType: authType,
            onComplete: (bool success) => navigator.pop(success),
          ),
        ),
      );
    } else if (authType == 'BIOMETRIC') {
      return navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => OneAuthBiometricVerificationScreen(
            txnId: txnId,
            txnHash: txnHash,
            onComplete: (bool success) => navigator.pop(success),
          ),
        ),
      );
    }

    return false;
  }

  @override
  Future<void> startEnrollmentFlow(
    BuildContext context, {
    required OneAuthUser user,
    VoidCallback? onSuccess,
  }) async {
    final navigator = Navigator.of(context);

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => OneAuthSetupScreen(
          user: user,
          onConfirm: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => OneAuthStatusScreen(
                  user: user,
                  currentStep: 1,
                  onComplete: () {
                    navigator.pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => OneAuthVerificationModelScreen(
                          user: user,
                          onContinue: () {
                            navigator.popUntil((route) => route.isFirst);
                            if (onSuccess != null) {
                              onSuccess();
                            } else if (context.mounted) {
                              OneAuthSnackBar.show(
                                context,
                                message: 'OneAuth Activated Successfully!',
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          onCancel: () => navigator.pop(),
        ),
      ),
    );
  }
}
