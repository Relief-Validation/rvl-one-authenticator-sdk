import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/pin_input.dart';
import '../one_auth_impl.dart';
import '../models/user.dart';
import 'pin_setup_view_model.dart';
import 'package:dio/dio.dart';

class OneAuthPinSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final Function(String pin) onComplete;
  final Map<String, dynamic>? payload;
  final int pinLength;

  const OneAuthPinSetupScreen({
    super.key,
    required this.user,
    required this.onComplete,
    this.payload,
    this.pinLength = 4,
  });

  @override
  State<OneAuthPinSetupScreen> createState() => _OneAuthPinSetupScreenState();
}

class _OneAuthPinSetupScreenState extends State<OneAuthPinSetupScreen> {
  late final OneAuthPinSetupViewModel _viewModel;
  late final List<TextEditingController> _pinControllers;
  late final List<TextEditingController> _confirmPinControllers;
  late final List<FocusNode> _pinFocusNodes;
  late final List<FocusNode> _confirmPinFocusNodes;

  @override
  void initState() {
    super.initState();
    _viewModel = OneAuthPinSetupViewModel(user: widget.user, pinLength: widget.pinLength);
    _pinControllers = List.generate(widget.pinLength, (_) => TextEditingController());
    _confirmPinControllers = List.generate(widget.pinLength, (_) => TextEditingController());
    _pinFocusNodes = List.generate(widget.pinLength, (_) => FocusNode());
    _confirmPinFocusNodes = List.generate(widget.pinLength, (_) => FocusNode());
    _handlePayload();
  }

  void _handlePayload() {
    if (widget.payload != null && widget.payload!['pin'] != null) {
      final pin = widget.payload!['pin'].toString();
      if (pin.length == widget.pinLength) {
        for (int i = 0; i < widget.pinLength; i++) {
          _pinControllers[i].text = pin[i];
          _confirmPinControllers[i].text = pin[i];
        }
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var controller in _confirmPinControllers) {
      controller.dispose();
    }
    for (var node in _pinFocusNodes) {
      node.dispose();
    }
    for (var node in _confirmPinFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final pin = _pinControllers.map((c) => c.text).join();
    final confirmPin = _confirmPinControllers.map((c) => c.text).join();

    final success = await _viewModel.setupPin(pin, confirmPin);
    
    if (success) {
      if (mounted) widget.onComplete(pin);
    } else {
      if (_viewModel.errorMessage == 'PINs do not match. Please try again.') {
        // Clear confirm pin on mismatch
        for (var controller in _confirmPinControllers) {
          controller.clear();
        }
        _confirmPinFocusNodes[0].requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return Scaffold(
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
                          'Set up your PIN',
                          style: OneAuthTheme.headingStyle(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Create a ${widget.pinLength} Digit pin',
                          style: OneAuthTheme.subHeadingStyle(context),
                        ),
                        const SizedBox(height: 40),
                        _buildPinSection('Pin', _pinControllers, _pinFocusNodes, false),
                        const SizedBox(height: 32),
                        _buildPinSection('Confirm Pin', _confirmPinControllers, _confirmPinFocusNodes, true),
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
                    label: _viewModel.isLoading ? 'Setting up...' : 'Continue',
                    onPressed: _viewModel.isLoading ? null : _handleContinue,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinSection(String label, List<TextEditingController> controllers, List<FocusNode> focusNodes, bool isConfirm) {
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
          controllers: controllers,
          focusNodes: focusNodes,
          onChanged: (_) => _viewModel.clearError(),
          onFieldSubmitted: (pin, index) {
            if (!isConfirm && index == widget.pinLength - 1) {
              _confirmPinFocusNodes[0].requestFocus();
            }
          },
        ),
      ],
    );
  }
}
