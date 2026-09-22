import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:freerasp/freerasp.dart';

/// Represents a security threat detected on the device.
class SecurityThreatEvent {
  final String threatType;
  final String message;
  final DateTime timestamp;

  SecurityThreatEvent({
    required this.threatType,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'SecurityThreatEvent($threatType: $message at $timestamp)';
}

/// Snapshot of current device security state.
class DeviceSecurityState {
  final bool isRooted;
  final bool isEmulator;
  final bool isTampered;
  final bool isHooked;
  final bool isUntrusted;
  final bool isVpnActive;
  final SecurityThreatEvent? latestThreat;

  const DeviceSecurityState({
    this.isRooted = false,
    this.isEmulator = false,
    this.isTampered = false,
    this.isHooked = false,
    this.isUntrusted = false,
    this.isVpnActive = false,
    this.latestThreat,
  });

  /// Returns true if the device is secure for production operations.
  bool get isSecure {
    // In debug mode, untrusted/debugger is allowed
    final untrustedViolation = kReleaseMode ? isUntrusted : false;
    final emulatorViolation = kReleaseMode ? isEmulator : false;

    return !isRooted && !isTampered && !isHooked && !untrustedViolation && !emulatorViolation;
  }

  Map<String, dynamic> toMap() => {
        'rootedOrJailbroken': isRooted,
        'emulatorDetected': isEmulator,
        'appTamperDetected': isTampered,
        'hookDetected': isHooked,
        'deviceUntrusted': isUntrusted,
        'vpnActive': isVpnActive,
        'isSecure': isSecure,
        'latestThreat': latestThreat?.message,
      };
}

/// Standalone manager class for RASP threat detection and device security monitoring.
///
/// Publishes real-time threat data via [threatStream] and [ChangeNotifier]
/// so existing UI and services can consume security status without special UI wrappers.
class SecurityService with ChangeNotifier {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  bool _isInitialized = false;

  DeviceSecurityState _state = const DeviceSecurityState();

  final StreamController<SecurityThreatEvent> _threatStreamController =
      StreamController<SecurityThreatEvent>.broadcast();

  /// Stream emitting threat events in real-time.
  Stream<SecurityThreatEvent> get threatStream => _threatStreamController.stream;

  /// Current device security state snapshot.
  DeviceSecurityState get state => _state;

  /// Whether the device passes security checks.
  bool get isSecure => _state.isSecure;

  /// Latest threat detected, if any.
  SecurityThreatEvent? get latestThreat => _state.latestThreat;

  /// Whether security monitoring is initialized and running.
  bool get isInitialized => _isInitialized;

  static const MethodChannel _securityChannel = MethodChannel('com.example.one_auth/crypto');

  /// Dynamically retrieves the active app's Base64 SHA-256 signing certificate hash.
  static Future<String?> getAppSigningHash() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final String? hash = await _securityChannel.invokeMethod<String>('getAppSigningHash');
        if (hash != null && hash.isNotEmpty) {
          debugPrint('SecurityService: Dynamically resolved active signing hash -> $hash');
          return hash;
        }
      }
    } catch (e) {
      debugPrint('SecurityService: Dynamic signing hash lookup note: $e');
    }
    return null;
  }

  /// Initializes freeRASP security monitoring and attaches threat listeners.
  Future<void> initialize({
    required String packageName,
    required List<String> androidSigningHashes,
    String? iosBundleId,
    String? iosTeamId,
    String watcherMail = 'security@dginfotech.com',
  }) async {
    if (_isInitialized) return;

    final List<String> certHashes = List.from(androidSigningHashes);

    // Auto-detect dynamic active certificate hash if list is empty or doesn't contain it
    final dynamicHash = await getAppSigningHash();
    if (dynamicHash != null && !certHashes.contains(dynamicHash)) {
      certHashes.add(dynamicHash);
    }

    final callback = ThreatCallback(
      onPrivilegedAccess: () => _handleThreat('Root/Jailbreak', 'Privileged access detected on device.'),
      onSimulator: () => _handleThreat('Simulator', 'Device running inside simulator/emulator.'),
      onAppIntegrity: () => _handleThreat('App Tampering', 'App integrity check failed or binary modified.'),
      onHooks: () => _handleThreat('Hooking Framework', 'Dynamic instrumentation or hooking detected (e.g. Frida).'),
      onDebug: () {
        if (kReleaseMode) {
          _handleThreat('Debugger Attached', 'App running with debugger attached in release mode.');
        } else {
          debugPrint('SecurityService: Debugger detected but ignored in kDebugMode.');
        }
      },
      onDeviceBinding: () => _handleThreat('Device Binding', 'Device binding validation failed.'),
      onUnofficialStore: () => _handleThreat('Unofficial Store', 'App installed from an untrusted store.'),
      onSystemVPN: () => _handleThreat('VPN Active', 'Active VPN connection detected.'),
    );

    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: packageName,
        signingCertHashes: certHashes,
      ),
      iosConfig: IOSConfig(
        bundleIds: [iosBundleId ?? packageName],
        teamId: iosTeamId ?? 'UNKNOWN_TEAM_ID',
      ),
      watcherMail: watcherMail,
    );

    try {
      Talsec.instance.attachListener(callback);
      await Talsec.instance.start(config);
      _isInitialized = true;
      debugPrint('SecurityService: RASP security monitoring started successfully.');
    } catch (e) {
      debugPrint('SecurityService: Failed to start security monitoring: $e');
    }
  }

  void _handleThreat(String type, String message) {
    final event = SecurityThreatEvent(threatType: type, message: message);

    _state = DeviceSecurityState(
      isRooted: type == 'Root/Jailbreak' || _state.isRooted,
      isEmulator: type == 'Simulator' || _state.isEmulator,
      isTampered: type == 'App Tampering' || _state.isTampered,
      isHooked: type == 'Hooking Framework' || _state.isHooked,
      isUntrusted: (type == 'Debugger Attached' || type == 'Unofficial Store' || type == 'Device Binding') ||
          _state.isUntrusted,
      isVpnActive: type == 'VPN Active' || _state.isVpnActive,
      latestThreat: event,
    );

    debugPrint('SecurityService [THREAT DETECTED]: $type - $message');

    // Push threat data to broadcast stream
    _threatStreamController.add(event);

    // Notify all UI listeners / Providers
    notifyListeners();
  }

  /// Emits a simulated threat event for testing real-time stream listeners.
  @visibleForTesting
  void emitThreatForTesting(String type, String message) {
    _handleThreat(type, message);
  }

  /// Evaluates security and returns snapshot.
  Future<DeviceSecurityState> verifySecurity() async {
    return _state;
  }

  @override
  void dispose() {
    _threatStreamController.close();
    super.dispose();
  }
}
