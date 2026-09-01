import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../models/user.dart';
import '../one_auth_impl.dart';

import '../widgets/snack_bar.dart';

class OneAuthBiometricSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback onComplete;

  const OneAuthBiometricSetupScreen({
    super.key,
    required this.user,
    required this.onComplete,
  });

  @override
  State<OneAuthBiometricSetupScreen> createState() => _OneAuthBiometricSetupScreenState();
}

class _OneAuthBiometricSetupScreenState extends State<OneAuthBiometricSetupScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isEnrolled = false;
  IconData _biometricIcon = Icons.fingerprint;
  String _biometricTypeLabel = 'fingerprint or face';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final List<BiometricType> availableBiometrics = await auth.getAvailableBiometrics();

      if (mounted) {
        setState(() {
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
      }
    } catch (e) {
      debugPrint('Error checking biometrics: $e');
    }
  }

  Future<void> _handleEnrollment() async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();

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
        localizedReason: 'Please authenticate to enable OneAuth biometrics',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate && mounted) {
        setState(() => _isEnrolled = true);
        
        await OneAuth().submitCsr(
          widget.user.copyWith(preferredAuthenticationType: 'BIOMETRIC'),
        );
        
        if (mounted) {
          widget.onComplete();
        }
      }
    } catch (e) {
      debugPrint('Error during biometric authentication: $e');
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Biometric authentication failed: ${e.toString()}',
          isError: true,
        );
      }
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
              'Use your $_biometricTypeLabel to securely and quickly access OneAuth.',
              textAlign: TextAlign.center,
              style: OneAuthTheme.subHeadingStyle(context),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _isEnrolled ? null : _handleEnrollment,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _isEnrolled ? Icons.check_circle : _biometricIcon,
                  key: ValueKey<bool>(_isEnrolled),
                  size: 120,
                  color: _isEnrolled ? Colors.green : Colors.cyan[400],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isEnrolled ? 'Biometric Enabled!' : 'Tap below to enable',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _isEnrolled ? Colors.green : OneAuthTheme.getPrimaryTextColor(context),
              ),
            ),
            const Spacer(),
            OneAuthPrimaryButton(
              label: 'Enable Biometric',
              onPressed: _handleEnrollment,
              isEnabled: !_isEnrolled,
            ),
          ],
        ),
      ),
    );
  }
}
