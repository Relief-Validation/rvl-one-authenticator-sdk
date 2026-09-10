import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/theme.dart';
import '../core/totp_generator.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/pin_input.dart';
import '../widgets/notification_banner.dart';
import '../one_auth_impl.dart';
import 'pin_verification_view_model.dart';

class OneAuthPinVerificationScreen extends StatefulWidget {
  final String txnId;
  final String txnHash;
  final String? numberMatchingCode;
  final VoidCallback onComplete;
  final int pinLength;

  const OneAuthPinVerificationScreen({
    super.key,
    required this.txnId,
    required this.txnHash,
    this.numberMatchingCode,
    required this.onComplete,
    this.pinLength = 4,
  });

  @override
  State<OneAuthPinVerificationScreen> createState() => _OneAuthPinVerificationScreenState();
}

class _OneAuthPinVerificationScreenState extends State<OneAuthPinVerificationScreen> {
  late final OneAuthPinVerificationViewModel _viewModel;
  late final List<TextEditingController> _pinControllers;
  late final List<FocusNode> _pinFocusNodes;
  String _currentCode = '';
  bool _showNotification = false;

  @override
  void initState() {
    super.initState();
    _viewModel = OneAuthPinVerificationViewModel(
      txnId: widget.txnId,
      txnHash: widget.txnHash,
      numberMatchingCode: widget.numberMatchingCode,
      pinLength: widget.pinLength,
    );
    _pinControllers = List.generate(widget.pinLength, (_) => TextEditingController());
    _pinFocusNodes = List.generate(widget.pinLength, (_) => FocusNode());

    if (widget.pinLength == 6) {
      _showSimulatedPushNotification();
    }
  }

  void _showSimulatedPushNotification() {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      const storage = FlutterSecureStorage();
      final userId = await storage.read(key: 'authenticatorUserId');
      String? secret;
      if (userId != null && userId.isNotEmpty) {
        secret = await OneAuth().getTotpSecret(userId);
      }

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

  @override
  void dispose() {
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var node in _pinFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _handleVerify() async {
    final pin = _pinControllers.map((c) => c.text).join();
    final success = await _viewModel.verifyPin(pin);
    if (success && mounted) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
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
                              'Transaction Authorization',
                              style: OneAuthTheme.headingStyle(context),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.numberMatchingCode != null 
                                ? 'Confirm the code ${widget.numberMatchingCode} and enter your PIN'
                                : widget.pinLength == 6
                                    ? 'Enter your 6-digit TOTP code to authorize this transaction'
                                    : 'Enter your ${widget.pinLength}-digit PIN to authorize this transaction',
                              textAlign: TextAlign.center,
                              style: OneAuthTheme.subHeadingStyle(context),
                            ),
                            const SizedBox(height: 40),
                            _buildPinSection(
                              widget.pinLength == 6 ? 'Enter TOTP Code' : 'Enter PIN',
                              _pinControllers,
                              _pinFocusNodes,
                            ),
                            if (_viewModel.errorMessage != null) ...[
                              const SizedBox(height: 24),
                              Text(
                                _viewModel.errorMessage!,
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
                        label: _viewModel.isLoading ? 'Authorizing...' : 'Authorize',
                        onPressed: _viewModel.isLoading ? null : _handleVerify,
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
      },
    );
  }

  Widget _buildPinSection(String label, List<TextEditingController> controllers, List<FocusNode> focusNodes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: OneAuthTheme.getPrimaryTextColor(context),
          ),
        ),
        const SizedBox(height: 12),
        OneAuthPinInput(
          length: widget.pinLength,
          obscureText: widget.pinLength != 6,
          controllers: controllers,
          focusNodes: focusNodes,
          onChanged: (pin) => _viewModel.clearError(),
          onFieldSubmitted: (pin, index) => _handleVerify(),
        ),
      ],
    );
  }
}
