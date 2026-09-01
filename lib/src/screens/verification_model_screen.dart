import 'package:flutter/material.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../one_auth_impl.dart';
import '../models/authentication_type.dart';
import '../models/user.dart';
import 'pin_setup_screen.dart';
import 'biometric_setup_screen.dart';
import 'totp_setup_screen.dart';
import 'push_setup_screen.dart';

class OneAuthVerificationModelScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback onContinue;

  const OneAuthVerificationModelScreen({
    super.key,
    required this.user,
    required this.onContinue,
  });

  @override
  State<OneAuthVerificationModelScreen> createState() => _OneAuthVerificationModelScreenState();
}

class _OneAuthVerificationModelScreenState extends State<OneAuthVerificationModelScreen> {
  String? _selectedModelCode;
  List<AuthenticationType> _authTypes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAuthenticationTypes();
  }

  Future<void> _fetchAuthenticationTypes() async {
    try {
      final response = await OneAuth().dio.get('/client/authentication-types');
      final List<dynamic> data = response.data;
      setState(() {
        _authTypes = data.map((e) => AuthenticationType.fromJson(e)).toList();
        _authTypes.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        if (_authTypes.isNotEmpty) {
          _selectedModelCode = _authTypes.first.code;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching authentication types: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const OneAuthAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(
                          child: Text(
                            'Select Default Verification Model',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'A One Authenticator profile has been created from your Bank details and your identity has been verified.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_authTypes.isEmpty)
                          const Center(child: Text('No verification models available.'))
                        else
                          ..._authTypes.map((model) => _buildModelOption(model)),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: OneAuthPrimaryButton(
              label: 'Continue',
              onPressed: _isLoading || _selectedModelCode == null
                  ? null
                  : () {
                      if (_selectedModelCode == 'PIN') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneAuthPinSetupScreen(
                              user: widget.user,
                              onComplete: (pin) => widget.onContinue(),
                            ),
                          ),
                        );
                      } else if (_selectedModelCode == 'BIOMETRIC') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneAuthBiometricSetupScreen(
                              user: widget.user,
                              onComplete: widget.onContinue,
                            ),
                          ),
                        );
                      } else if (_selectedModelCode == 'TOTP') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneAuthTotpSetupScreen(
                              user: widget.user,
                              onComplete: widget.onContinue,
                            ),
                          ),
                        );
                      } else if (_selectedModelCode == 'PUSH') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneAuthPushSetupScreen(
                              user: widget.user,
                              type: PushSetupType.approval,
                              onComplete: widget.onContinue,
                            ),
                          ),
                        );
                      } else if (_selectedModelCode == 'NUMBER_MATCHING') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OneAuthPushSetupScreen(
                              user: widget.user,
                              type: PushSetupType.matching,
                              onComplete: widget.onContinue,
                            ),
                          ),
                        );
                      } else {
                        widget.onContinue();
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelOption(AuthenticationType model) {
    final isSelected = _selectedModelCode == model.code;

    return GestureDetector(
      onTap: () => setState(() => _selectedModelCode = model.code),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.grey[300]!,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.blueAccent : Colors.grey[600]!,
                  width: 2,
                ),
              ),
              child: Center(
                child: isSelected
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (model.description.isNotEmpty)
                    Text(
                      model.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

