import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../core/totp_generator.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/notification_banner.dart';
import '../models/user.dart';
import '../one_auth_impl.dart';

class OneAuthTotpSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback onComplete;

  const OneAuthTotpSetupScreen({
    super.key,
    required this.user,
    required this.onComplete,
  });

  @override
  State<OneAuthTotpSetupScreen> createState() => _OneAuthTotpSetupScreenState();
}

class _OneAuthTotpSetupScreenState extends State<OneAuthTotpSetupScreen> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  String? _errorMessage;
  String _currentCode = '';
  bool _showNotification = false;

  @override
  void initState() {
    super.initState();
    _showSimulatedPushNotification();
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _showSimulatedPushNotification() {
    // Simulate a push notification arriving after a short delay
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      // In a real application, the secret is retrieved from secure storage.
      // It is provisioned during user enrollment (e.g., via QR code scan).
      String? secret = await OneAuth().getTotpSecret(widget.user.id);
      
      if (secret == null) {
        final csrPem = await OneAuth().getCsrPem();
        if (csrPem != null && csrPem.isNotEmpty) {
          secret = OneAuthTotpGenerator.generateSecretFromPublicKeyPem(csrPem);
        }
      }

      if (secret == null || secret.isEmpty) {
        debugPrint('OneAuth: No TOTP secret or CSR PEM found to generate TOTP code.');
        return;
      }
      
      final code = OneAuthTotpGenerator.generateCode(secret);

      if (!mounted) return;

      setState(() {
        _currentCode = code;
        _showNotification = true;
      });

      // Auto-hide after 30 seconds
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _showNotification) {
          setState(() => _showNotification = false);
        }
      });
    });
  }

  void _onChanged(String value, int index) {
    if (value.length > 1) {
      // Handle paste
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      
      // If it's a 6-digit code, always fill from the start
      final startIdx = digits.length >= 6 ? 0 : index;
      
      for (var i = 0; i < digits.length && (startIdx + i) < 6; i++) {
        _controllers[startIdx + i].text = digits[i];
      }
      
      // Move focus to the end of pasted digits or last box
      final nextIndex = (startIdx + digits.length).clamp(0, 5);
      _focusNodes[nextIndex].requestFocus();
    } else if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _handleVerify() async {
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code');
      return;
    }

    try {
      await OneAuth().submitCsr(
        widget.user.copyWith(
          preferredAuthenticationType: 'TOTP',
          totpCode: code,
        ),
      );
      widget.onComplete();
    } catch (e) {
      setState(() => _errorMessage = 'Verification Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: OneAuthTheme.getBackgroundColor(context),
          appBar: const OneAuthAppBar(),
          body: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          'TOTP Verification',
                          style: OneAuthTheme.headingStyle(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Enter the 6-digit code from your authenticator app to link your account.',
                          textAlign: TextAlign.center,
                          style: OneAuthTheme.subHeadingStyle(context),
                        ),
                        const SizedBox(height: 40),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 50,
                              height: 70,
                              child: TextField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontSize: 24, 
                                  fontWeight: FontWeight.bold,
                                  color: OneAuthTheme.getPrimaryTextColor(context),
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: EdgeInsets.zero,
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: OneAuthTheme.getBorderColor(context),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: OneAuthColors.primaryBlue, width: 2),
                                  ),
                                ),
                                onChanged: (v) => _onChanged(v, index),
                              ),
                            );
                          }),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: OneAuthPrimaryButton(
                    label: 'Verify and Activate',
                    onPressed: _handleVerify,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showNotification)
          OneAuthNotificationBanner(
            code: _currentCode,
            onDismiss: () => setState(() => _showNotification = false),
          ),
      ],
    );
  }
}
