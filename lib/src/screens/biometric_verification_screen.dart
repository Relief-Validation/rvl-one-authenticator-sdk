import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/snack_bar.dart';
import '../one_auth_impl.dart';

/// Screen displayed when authorizing a transaction requiring Biometric verification.
class OneAuthBiometricVerificationScreen extends StatefulWidget {
  final String txnId;
  final String txnHash;
  final Function onComplete;

  const OneAuthBiometricVerificationScreen({
    super.key,
    required this.txnId,
    required this.txnHash,
    required this.onComplete,
  });

  @override
  State<OneAuthBiometricVerificationScreen> createState() =>
      _OneAuthBiometricVerificationScreenState();
}

class _OneAuthBiometricVerificationScreenState
    extends State<OneAuthBiometricVerificationScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isVerifying = false;
  bool _isAuthenticated = false;
  IconData _biometricIcon = Icons.fingerprint;
  String _biometricTypeLabel = 'fingerprint or face';
  StreamSubscription? _pushSubscription;

  String get _effectiveTxnId {
    if (widget.txnId.isNotEmpty) return widget.txnId;
    final latestData = OneAuth().latestPushChallengeData;
    return latestData?['txnId']?.toString() ?? '';
  }

  String get _effectiveTxnHash {
    if (widget.txnHash.isNotEmpty) return widget.txnHash;
    final latestData = OneAuth().latestPushChallengeData;
    return latestData?['txnHash']?.toString() ?? '';
  }

  @override
  void initState() {
    super.initState();

    // Listen to push challenge stream for verification status updates
    _pushSubscription = OneAuth().onPushChallengeReceived.listen((data) {
      if (mounted) {
        final status = data['status']?.toString().toUpperCase();
        if (status == 'VERIFIED' || status == 'SUCCESS' || status == 'APPROVED') {
          OneAuthSnackBar.show(context, message: 'Biometric Verification Approved!');
          _notifyComplete(true);
        } else if (status == 'DECLINED' || status == 'DENIED' || status == 'REJECTED' || status == 'FAILED') {
          OneAuthSnackBar.show(context, message: 'Biometric Verification Denied.', isError: true);
          _notifyComplete(false);
        }
      }
    });

    // Schedule check and prompt after the first frame completes to prevent setState during build error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkBiometricsAndPrompt();
      }
    });
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _notifyComplete(bool success) {
    final callback = widget.onComplete;
    if (callback is void Function(bool)) {
      callback(success);
    } else if (callback is void Function()) {
      callback();
    } else {
      Function.apply(callback, [success]);
    }
  }

  Future<void> _checkBiometricsAndPrompt() async {
    try {
      final List<BiometricType> availableBiometrics =
          await auth.getAvailableBiometrics();

      if (!mounted) return;

      _safeSetState(() {
        if (availableBiometrics.contains(BiometricType.face)) {
          _biometricIcon = Icons.face;
          _biometricTypeLabel = 'face';
        } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
          _biometricIcon = Icons.fingerprint;
          _biometricTypeLabel = 'fingerprint';
        } else if (availableBiometrics.contains(BiometricType.iris)) {
          _biometricIcon = Icons.visibility;
          _biometricTypeLabel = 'iris';
        }
      });

      // Automatically trigger biometric authentication prompt after frame build & biometrics check
      if (mounted) {
        _handleBiometricAuth();
      }
    } catch (e) {
      debugPrint('Error checking biometrics: $e');
    }
  }

  Future<void> _handleBiometricAuth() async {
    if (!mounted || _isVerifying || _isAuthenticated) return;

    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        if (mounted) {
          OneAuthSnackBar.show(
            context,
            message: 'Biometric authentication is not available on this device.',
            isError: true,
          );
        }
        return;
      }

      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to authorize this transaction',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!mounted) return;

      if (didAuthenticate) {
        final txnId = _effectiveTxnId;
        final txnHash = _effectiveTxnHash;

        if (txnId.isEmpty || txnHash.isEmpty) {
          if (mounted) {
            OneAuthSnackBar.show(
              context,
              message: 'Transaction ID or Hash is missing.',
              isError: true,
            );
          }
          return;
        }

        _safeSetState(() {
          _isVerifying = true;
        });

        await OneAuth().submitTransactionSignature(
          txnId: txnId,
          txnHash: txnHash,
          pin: 'BIOMETRIC_APPROVED',
          authType: 'BIOMETRIC',
          userResponse: 'true',
        );

        if (!mounted) return;

        _safeSetState(() {
          _isAuthenticated = true;
        });

        OneAuthSnackBar.show(
          context,
          message: 'Biometric Verification Approved!',
        );
        _notifyComplete(true);
      }
    } catch (e) {
      debugPrint('Error during biometric verification: $e');
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Biometric authentication failed: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      _safeSetState(() {
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      appBar: const OneAuthAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              'Biometric Verification',
              style: OneAuthTheme.headingStyle(context),
            ),
            const SizedBox(height: 12),
            Text(
              'Use your $_biometricTypeLabel to authorize this transaction.',
              textAlign: TextAlign.center,
              style: OneAuthTheme.subHeadingStyle(context),
            ),
            const Spacer(),
            GestureDetector(
              onTap: (_isVerifying || _isAuthenticated)
                  ? null
                  : _handleBiometricAuth,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isAuthenticated ? Icons.check_circle : _biometricIcon,
                  key: ValueKey<bool>(_isAuthenticated),
                  size: 120,
                  color: _isAuthenticated
                      ? Colors.green
                      : Colors.cyan[400],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isAuthenticated
                  ? 'Verification Successful!'
                  : _isVerifying
                      ? 'Verifying transaction...'
                      : 'Tap icon or button below to authenticate',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _isAuthenticated
                    ? Colors.green
                    : OneAuthTheme.getPrimaryTextColor(context),
              ),
            ),
            const Spacer(),
            OneAuthPrimaryButton(
              label: _isVerifying
                  ? 'Authorizing...'
                  : 'Authenticate with Biometrics',
              onPressed: (_isVerifying || _isAuthenticated)
                  ? null
                  : _handleBiometricAuth,
              isEnabled: !_isVerifying && !_isAuthenticated,
            ),
          ],
        ),
      ),
    );
  }
}
