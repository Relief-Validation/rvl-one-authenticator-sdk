import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart' as pkg;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'one_auth_interface.dart';
import 'models/user.dart';
import 'api/dio_client.dart';
import 'core/env.dart';
import 'core/exceptions.dart';
import 'package:freerasp/freerasp.dart';

class OneAuth implements OneAuthInterface {
  static final OneAuth _instance = OneAuth._internal();

  factory OneAuth() => _instance;

  OneAuth._internal();

  static const _cryptoChannel = MethodChannel('com.example.one_auth/crypto');

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String? _clientSecret;
  String? _baseUrl;
  // String? _bankId;
  String? _clientToken;
  String? _userToken;
  String? _sessionToken;
  String? _nonceBase64;
  String? _authenticatorUserId;
  late DioClient _dioClient;
  bool _isInitialized = false;
  bool _isFreeRASPStarted = false;
  bool _isFreeRASPListenerAttached = false;
  DateTime? _lastSecurityCheck;

  // Device Integrity Flags (managed by freeRASP)
  bool _isRooted = false;
  bool _isEmulator = false;
  bool _isTampered = false;
  bool _isHooked = false;
  bool _isDeviceUntrusted = false;
  bool _isVpnActive = false;

  final StreamController<bool> _clientStatusController =
      StreamController<bool>.broadcast();

  @override
  Dio get dio => _dioClient.dio;

  @override
  void setUserToken(String? token) {
    _userToken = token;
    debugPrint('OneAuth: User Token updated.');
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
  }) async {
    if (_isInitialized) {
      debugPrint('OneAuth: SDK already initialized.');
      return;
    }
    debugPrint('OneAuth: Initializing Client SDK...');

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

    _isInitialized = true;
    debugPrint('OneAuth: SDK Initialization Complete.');
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
    final integrity = await _getDeviceIntegrity();
    _validateIntegrity(integrity, 'SDK Operation');

    _lastSecurityCheck = DateTime.now();
  }

  Future<void> _initFreeRASP({bool force = false}) async {
    if (_isFreeRASPStarted && !force) return; // Already running and no force requested

    try {
      final packageInfo = await pkg.PackageInfo.fromPlatform();
      final appPackageId = packageInfo.packageName;

      // Configuration for freeRASP
      final config = TalsecConfig(
        androidConfig: AndroidConfig(
          packageName: appPackageId,
          signingCertHashes: ['fDRHLiKQjSC2EYUoHfR8T0fG3hGFbc12tNbEsf2P0XM='], // for debug only
        ),
        iosConfig: IOSConfig(
          bundleIds: [appPackageId],
          teamId: 'YOUR_TEAM_ID_HERE',
        ),
        watcherMail: '', // unused in this version
      );

      // Only attach listener once to avoid duplicate callback triggers
      if (!_isFreeRASPListenerAttached) {
        final callback = ThreatCallback(
          onPrivilegedAccess: () => _isRooted = true,
          onSimulator: () => _isEmulator = true,
          onAppIntegrity: () => _isTampered = true,
          onHooks: () => _isHooked = true,
          onDeviceBinding: () => _isDeviceUntrusted = true,
          onUnofficialStore: () => _isDeviceUntrusted = true,
          onDebug: () => _isDeviceUntrusted = true,
          onSystemVPN: () => _isVpnActive = true,
        );

        Talsec.instance.attachListener(callback);
        _isFreeRASPListenerAttached = true;
      }

      // Start Talsec. This should be called only once.
      if (!_isFreeRASPStarted || force) {
        await Talsec.instance.start(config);
        
        // Settle period only on first start or forced restart
        await Future.delayed(const Duration(milliseconds: 1000));
        _isFreeRASPStarted = true;
      }
      
      debugPrint('OneAuth: freeRASP Security Monitoring Started/Verified.');
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

  Future<String> _getOrCreateId(String key, String prefix, {bool isAuthId = false}) async {
    String? id = await _secureStorage.read(key: key);
    if (id == null) {
      if (isAuthId) {
        final suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12).toUpperCase();
        id = '$prefix$suffix';
      } else {
        id = '$prefix${const Uuid().v4()}';
      }
      await _secureStorage.write(key: key, value: id);
    }
    return id;
  }

  @override
  Future<Map<String, dynamic>> enroll(OneAuthUser user) async {
    _ensureInitialized();
    debugPrint('OneAuth: Starting Enrollment Orchestration...');
    
    final integrity = await _getDeviceIntegrity();
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
    
    final integrity = await _getDeviceIntegrity();
    _validateIntegrity(integrity, 'CSR submission');

    // Use provided fresh tokens or fall back to instance variables (with a warning)
    final effectiveSessionToken = sessionToken ?? _sessionToken;
    final effectiveNonce = nonceBase64 ?? _nonceBase64;

    if (effectiveSessionToken == null || effectiveNonce == null) {
      debugPrint('OneAuth Error: Attempting to submit CSR without a valid session.');
      throw OneAuthSessionException(
        'No active enrollment session found. Please call enroll() or getEnrollmentNonce() first.',
      );
    }

    try {
      // Ensure we have a persistent formatted ID (Generated if missing)
      final authenticatorUserId = await _getOrCreateAuthenticatorId(user.id);
      final deviceUuid = await _getOrCreateId('device_uuid', '');
      final appInstanceId =
          await _getOrCreateId('app_instance_id', 'instance-');

      // Validation: Ensure DOB is in YYYY-MM-DD format
      if (user.dob != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(user.dob!)) {
        debugPrint('OneAuth Warning: DOB "${user.dob}" might not match server format YYYY-MM-DD');
      }

      String osVersion = 'Unknown';
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        osVersion =
            'Android ${androidInfo.version.release} / API ${androidInfo.version.sdkInt}';
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        osVersion = 'iOS ${iosInfo.systemVersion}';
      }

      String csrPem = '-----BEGIN CERTIFICATE REQUEST-----\n...';
      List<dynamic> attestationChain = ["..."];

      if (Platform.isAndroid) {
        debugPrint(
            'OneAuth: Requesting hardware-backed CSR and Attestation from Android...');
        try {
          final result = await _cryptoChannel
              .invokeMapMethod<String, dynamic>('generateCsrAndAttestation', {
            'challenge': effectiveNonce,
            'identity': authenticatorUserId,
            'deviceUuid': deviceUuid,
          });
          if (result != null) {
            csrPem = result['csrPem'];
            attestationChain = result['attestationCertificateChain'];
            debugPrint('OneAuth: Received hardware-backed CSR.');
          }
        } on PlatformException catch (e) {
          debugPrint('OneAuth Native Error: [${e.code}] ${e.message}');
          debugPrint('OneAuth Native Details: ${e.details}');
          throw OneAuthCryptoException(
            'Native CSR generation failed: ${e.message}',
            code: e.code,
            originalError: e,
          );
        } catch (e) {
          debugPrint('OneAuth Unexpected Crypto Error: $e');
          throw OneAuthCryptoException(
            'Unexpected crypto error during CSR generation',
            originalError: e,
          );
        }
      }

      final payload = {
        "sessionToken": effectiveSessionToken,
        "customerUniqueKey": authenticatorUserId,
        "deviceUuid": deviceUuid,
        "csrPem": csrPem,
        "attestationCertificateChain": attestationChain,
        "accountNumber": user.accountNumber,
        "customerName": user.name,
        "nid": user.nid,
        "dob": user.dob,
        "mobile": user.phoneNumber,
        "email": user.email,
        "appInstanceId": appInstanceId,
        "osVersion": osVersion,
        "preferredAuthenticationType": user.preferredAuthenticationType,
        "pin": user.pin,
      };

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

      // Step 11: Persist the issued certificate and identifiers
      final data = response.data;
      final issuedCert =
          data['certificatePem'] ?? data['data']?['certificatePem'];
      final certificateSerial =
          data['certificateSerial'] ?? data['data']?['certificateSerial'];
      
      // Use server-provided ID if available, otherwise fall back to user-provided ID
      final serverCustomerId = data['authenticatorUserId'] ??
          data['data']?['authenticatorUserId'] ??
          authenticatorUserId;

      _authenticatorUserId = serverCustomerId;

      if (issuedCert != null) {
        await _secureStorage.write(
            key: 'issued_certificate', value: issuedCert);
        debugPrint('OneAuth: Issued certificate saved to secure storage.');
      }

      if (certificateSerial != null) {
        await _secureStorage.write(
            key: 'certificate_serial', value: certificateSerial.toString());
        debugPrint('OneAuth: Certificate serial saved to secure storage.');
      }

      await _secureStorage.write(key: 'authenticatorUserId', value: serverCustomerId);
      await _secureStorage.write(key: 'device_uuid', value: deviceUuid);
      
      debugPrint('OneAuth: CSR submitted successfully. Customer ID: $serverCustomerId');
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

  Future<Map<String, dynamic>> _getDeviceIntegrity() async {
    // Device Integrity using freeRASP (Talsec)
    // Provides real-time detection of root, emulator, tampering, and hooking.
    
    // Check VPN status manually if possible or rely on callback
    // For now, we rely on the freeRASP callbacks which are the most reliable.
    
    return {
      "rootedOrJailbroken": _isRooted,
      "emulatorDetected": _isEmulator,
      "appTamperDetected": _isTampered,
      "hookDetected": _isHooked,
      "deviceUntrusted": _isDeviceUntrusted,
      "vpnActive": _isVpnActive,
      "scanActive": _isFreeRASPStarted,
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
    String? selectedNumberMatchingCode,
  }) async {
    _ensureInitialized();
    
    // Always ensure security before signing
    await _ensureSecurity();

    debugPrint('OneAuth: Signing and submitting transaction $txnId...');

    // Initial check before starting the signing process
    final initialIntegrity = await _getDeviceIntegrity();
    _validateIntegrity(initialIntegrity, 'Transaction signing');

    final deviceUuid = await _secureStorage.read(key: 'device_uuid');
    final certificateSerial = await _secureStorage.read(key: 'certificate_serial');

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
    final finalIntegrity = await _getDeviceIntegrity();
    _validateIntegrity(finalIntegrity, 'Transaction submission');

    final payload = {
      "deviceUuid": deviceUuid,
      "certificateSerial": certificateSerial,
      "txnHash": txnHash,
      "signatureBase64": signatureBase64,
      "pinCode": pin,
      // "selectedNumberMatchingCode": selectedNumberMatchingCode,
      "deviceIntegrity": finalIntegrity,
    };

    developer.log('submitTransactionSignature request: $payload', name: 'OneAuth');

    try {
      final response = await _dioClient.dio.post(
        '/transactions/$txnId/signature',
        data: payload,
      );
      developer.log('submitTransactionSignature response: ${response.data}', name: 'OneAuth');
      
      final data = response.data;
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
}
