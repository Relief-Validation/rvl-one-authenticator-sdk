import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/theme.dart';
import '../../widgets/app_bar.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/pin_input.dart';
import '../../widgets/snack_bar.dart';
import '../../one_auth_impl.dart';
import '../../models/authentication_type.dart';
import '../../models/user.dart';

class OneAuthChangeAuthTypeScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback? onComplete;

  const OneAuthChangeAuthTypeScreen({
    super.key,
    required this.user,
    this.onComplete,
  });

  @override
  State<OneAuthChangeAuthTypeScreen> createState() => _OneAuthChangeAuthTypeScreenState();
}

class _OneAuthChangeAuthTypeScreenState extends State<OneAuthChangeAuthTypeScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  String? _selectedModelCode;
  String? _currentActiveModelCode;
  String? _sessionToken;
  String? _initiateMessage;
  List<AuthenticationType> _authTypes = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isCurrentVerified = false;

  @override
  void initState() {
    super.initState();
    _currentActiveModelCode = widget.user.preferredAuthenticationType;
    _selectedModelCode = null; // No pre-selection
    _initializeFlow();
  }

  Future<void> _initializeFlow() async {
    await Future.wait([
      _fetchAuthenticationTypes(),
      _initiateSession(),
    ]);
  }

  Future<void> _initiateSession() async {
    try {
      final res = await OneAuth().initiateAuthTypeChange(widget.user.id);
      if (mounted) {
        setState(() {
          _sessionToken = res['sessionToken'];
          if (res['currentAuthenticationType'] != null &&
              (res['currentAuthenticationType'] as String).isNotEmpty) {
            _currentActiveModelCode = res['currentAuthenticationType'];
          }
          if (res['message'] != null) {
            _initiateMessage = res['message'];
          }
        });
      }
    } catch (e) {
      debugPrint('OneAuth: Error initiating auth type change session: $e');
    }
  }

  Future<void> _fetchAuthenticationTypes() async {
    try {
      final response = await OneAuth().dio.get('/client/authentication-types');
      if (response.data != null && response.data is List) {
        final List<dynamic> data = response.data;
        final fetchedTypes = data.map((e) => AuthenticationType.fromJson(e)).toList();
        fetchedTypes.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        if (mounted) {
          setState(() {
            _authTypes = fetchedTypes;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('OneAuth: Error fetching authentication types: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  IconData _getIconForCode(String code) {
    switch (code.toUpperCase()) {
      case 'PIN':
        return Icons.lock_outline;
      case 'BIOMETRIC':
        return Icons.fingerprint;
      case 'TOTP':
        return Icons.vpn_key_outlined;
      case 'PUSH':
      case 'PUSH_NOTIFICATION':
        return Icons.notifications_active_outlined;
      case 'NUMBER_MATCHING':
        return Icons.dialpad;
      default:
        return Icons.security;
    }
  }

  Future<void> _handleUpdateAuthType() async {
    if (_selectedModelCode == null || _isSubmitting) return;

    if (_selectedModelCode == _currentActiveModelCode) {
      OneAuthSnackBar.show(
        context,
        message: 'This is already your active authentication type.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Step 1: Verify current auth type if not already verified
      if (!_isCurrentVerified) {
        final verified = await _verifyCurrentAuthType();
        if (!verified) {
          setState(() => _isSubmitting = false);
          return;
        }
        _isCurrentVerified = true;
      }

      // Step 2: Confirm new authentication type
      await _confirmNewAuthType();
    } catch (e) {
      debugPrint('OneAuth: Error in auth type change flow: $e');
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Failed to change auth type: ${e.toString()}',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Verification of Current Authentication Type
  Future<bool> _verifyCurrentAuthType() async {
    final currentType = (_currentActiveModelCode ?? 'PIN').toUpperCase();

    if (currentType == 'PIN') {
      final pin = await _promptPinModal(
        title: 'Verify Current PIN',
        subtitle: 'Please enter your current 4-digit PIN code to authorize this change.',
      );
      if (pin == null || pin.isEmpty) return false;

      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
        pinCode: pin,
      );

      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return res['verified'] == true || res['status'] == 'VERIFIED';
    } else if (currentType == 'BIOMETRIC') {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to verify your current biometric credentials',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (!authenticated) return false;

      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
        userResponse: 'true',
      );

      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return res['verified'] == true || res['status'] == 'VERIFIED';
    } else if (currentType == 'TOTP') {
      final totp = await _promptTotpModal(
        title: 'Verify Authenticator Code',
        subtitle: 'Enter the 6-digit TOTP code from your authenticator app.',
      );
      if (totp == null || totp.isEmpty) return false;

      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
        totpCode: totp,
      );

      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return res['verified'] == true || res['status'] == 'VERIFIED';
    } else if (currentType.contains('PUSH')) {
      final approved = await _promptPushModal(
        title: 'Verify Push Notification',
        subtitle: 'Tap Approve on the simulated push notification to verify your identity.',
      );
      if (approved != 'true') return false;

      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
        userResponse: 'true',
      );

      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return res['verified'] == true || res['status'] == 'VERIFIED';
    } else if (currentType.contains('NUMBER') || currentType.contains('MATCH')) {
      final selectedNum = await _promptNumberMatchingModal(
        title: 'Verify Number Matching',
        subtitle: 'Select the matching number to verify your current authentication method.',
      );
      if (selectedNum == null || selectedNum.isEmpty) return false;

      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
        userResponse: selectedNum,
      );

      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return res['verified'] == true || res['status'] == 'VERIFIED';
    } else {
      final res = await OneAuth().verifyAuthTypeChange(
        sessionToken: _sessionToken ?? '',
        customerUniqueKey: widget.user.id,
      );
      if (res['sessionToken'] != null) {
        _sessionToken = res['sessionToken'];
      }
      return true;
    }
  }

  /// Confirmation of New Authentication Type
  Future<void> _confirmNewAuthType() async {
    final targetType = _selectedModelCode!.toUpperCase();
    String? pinCode;
    String? totpCode;
    String? userResponse;

    if (targetType == 'PIN') {
      pinCode = await _promptPinSetupModal(
        title: 'Set up your PIN',
        subtitle: 'Create a 4 Digit pin',
      );
      if (pinCode == null || pinCode.isEmpty) return;
    } else if (targetType == 'TOTP') {
      totpCode = await _promptTotpModal(
        title: 'Confirm TOTP Code',
        subtitle: 'Enter the 6-digit code to verify your new TOTP authenticator setup.',
      );
      if (totpCode == null || totpCode.isEmpty) return;
    } else if (targetType == 'BIOMETRIC') {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to activate biometric verification for OneAuth',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (!authenticated) {
        if (mounted) {
          OneAuthSnackBar.show(
            context,
            message: 'Biometric authentication cancelled.',
            isError: true,
          );
        }
        return;
      }
      userResponse = 'true';
    } else if (targetType.contains('PUSH')) {
      userResponse = await _promptPushModal(
        title: 'Activate Push Notification',
        subtitle: 'Tap Approve on the push notification banner to activate Push Approval.',
      );
      if (userResponse != 'true') return;
    } else if (targetType.contains('NUMBER') || targetType.contains('MATCH')) {
      userResponse = await _promptNumberMatchingModal(
        title: 'Activate Number Matching',
        subtitle: 'Select the matching number to activate Number Matching challenge.',
      );
      if (userResponse == null || userResponse.isEmpty) return;
    }

    final res = await OneAuth().confirmAuthTypeChange(
      sessionToken: _sessionToken ?? '',
      customerUniqueKey: widget.user.id,
      preferredAuthenticationType: _selectedModelCode!,
      pinCode: pinCode,
      totpCode: totpCode,
      userResponse: userResponse,
    );

    if (mounted) {
      OneAuthSnackBar.show(
        context,
        message: res['message'] ?? 'Authentication type updated to ${_selectedModelCode!} successfully!',
      );

      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        Navigator.pop(context);
      }
    }
  }

  /// PIN Modal Bottom Sheet Prompt
  Future<String?> _promptPinModal({required String title, required String subtitle}) {
    final controllers = List.generate(4, (_) => TextEditingController());
    final focusNodes = List.generate(4, (_) => FocusNode());
    String currentPin = '';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: OneAuthTheme.headingStyle(ctx)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: OneAuthTheme.subHeadingStyle(ctx),
              ),
              const SizedBox(height: 28),
              OneAuthPinInput(
                length: 4,
                controllers: controllers,
                focusNodes: focusNodes,
                onChanged: (val) => currentPin = val,
                onFieldSubmitted: (val, _) {
                  if (val.length == 4) {
                    Navigator.pop(ctx, val);
                  }
                },
              ),
              const SizedBox(height: 32),
              OneAuthPrimaryButton(
                label: 'Confirm',
                onPressed: () {
                  if (currentPin.length == 4) {
                    Navigator.pop(ctx, currentPin);
                  } else {
                    OneAuthSnackBar.show(ctx, message: 'Please enter a valid 4-digit PIN', isError: true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// PIN Setup Bottom Sheet Prompt (with Pin and Confirm Pin fields)
  Future<String?> _promptPinSetupModal({required String title, required String subtitle}) {
    final pinControllers = List.generate(4, (_) => TextEditingController());
    final confirmPinControllers = List.generate(4, (_) => TextEditingController());
    final pinFocusNodes = List.generate(4, (_) => FocusNode());
    final confirmPinFocusNodes = List.generate(4, (_) => FocusNode());

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setModalState) {
            void handleSubmit() {
              final pin = pinControllers.map((c) => c.text).join();
              final confirmPin = confirmPinControllers.map((c) => c.text).join();

              if (pin.length < 4 || confirmPin.length < 4) {
                setModalState(() {
                  errorMessage = 'Please enter a 4-digit PIN in both sections.';
                });
                return;
              }

              if (pin != confirmPin) {
                setModalState(() {
                  errorMessage = 'PINs do not match. Please try again.';
                  for (var c in confirmPinControllers) {
                    c.clear();
                  }
                });
                confirmPinFocusNodes[0].requestFocus();
                return;
              }

              Navigator.pop(context, pin);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(title, style: OneAuthTheme.headingStyle(context)),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: OneAuthTheme.subHeadingStyle(context),
                  ),
                  const SizedBox(height: 28),

                  // Pin Section
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pin',
                      style: TextStyle(
                        fontSize: 16,
                        color: OneAuthTheme.getPrimaryTextColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OneAuthPinInput(
                    length: 4,
                    controllers: pinControllers,
                    focusNodes: pinFocusNodes,
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setModalState(() => errorMessage = null);
                      }
                    },
                    onFieldSubmitted: (_, index) {
                      if (index == 3) {
                        confirmPinFocusNodes[0].requestFocus();
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // Confirm Pin Section
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Confirm Pin',
                      style: TextStyle(
                        fontSize: 16,
                        color: OneAuthTheme.getPrimaryTextColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OneAuthPinInput(
                    length: 4,
                    controllers: confirmPinControllers,
                    focusNodes: confirmPinFocusNodes,
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setModalState(() => errorMessage = null);
                      }
                    },
                    onFieldSubmitted: (_, index) {
                      if (index == 3) {
                        handleSubmit();
                      }
                    },
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 32),
                  OneAuthPrimaryButton(
                    label: 'Continue',
                    onPressed: handleSubmit,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// TOTP Modal Bottom Sheet Prompt
  Future<String?> _promptTotpModal({required String title, required String subtitle}) {
    final controllers = List.generate(6, (_) => TextEditingController());
    final focusNodes = List.generate(6, (_) => FocusNode());
    String currentCode = '';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: OneAuthTheme.headingStyle(ctx)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: OneAuthTheme.subHeadingStyle(ctx),
              ),
              const SizedBox(height: 28),
              OneAuthPinInput(
                length: 6,
                controllers: controllers,
                focusNodes: focusNodes,
                obscureText: false,
                onChanged: (val) => currentCode = val,
                onFieldSubmitted: (val, _) {
                  if (val.length == 6) {
                    Navigator.pop(ctx, val);
                  }
                },
              ),
              const SizedBox(height: 32),
              OneAuthPrimaryButton(
                label: 'Confirm',
                onPressed: () {
                  if (currentCode.length == 6) {
                    Navigator.pop(ctx, currentCode);
                  } else {
                    OneAuthSnackBar.show(ctx, message: 'Please enter a valid 6-digit code', isError: true);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Push Approval Bottom Sheet Prompt
  Future<String?> _promptPushModal({required String title, required String subtitle}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: OneAuthTheme.headingStyle(ctx)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: OneAuthTheme.subHeadingStyle(ctx),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: OneAuthTheme.isDarkMode(ctx) ? Colors.white10 : const Color(0xFFF0F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OneAuthColors.primaryBlue, width: 1.5),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.security, color: OneAuthColors.primaryBlue),
                        SizedBox(width: 8),
                        Text('OneAuth Push Challenge', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Approve authentication request to proceed?'),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'false'),
                          child: const Text('Deny', style: TextStyle(color: Colors.red)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, 'true'),
                          style: ElevatedButton.styleFrom(backgroundColor: OneAuthColors.primaryBlue),
                          child: const Text('Approve', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Number Matching Bottom Sheet Prompt
  Future<String?> _promptNumberMatchingModal({required String title, required String subtitle}) {
    final choices = ['108', '042', '085'];
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: OneAuthTheme.headingStyle(ctx)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: OneAuthTheme.subHeadingStyle(ctx),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: choices.map((n) {
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, n),
                    child: Container(
                      width: 72,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EEF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OneAuthColors.primaryBlue, width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          n,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = OneAuthTheme.isDarkMode(context);

    return Scaffold(
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      appBar: const OneAuthAppBar(title: 'Change Auth Type'),
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
                        Text(
                          'Select Preferred Auth Type',
                          style: OneAuthTheme.headingStyle(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _initiateMessage ??
                              'Choose how you want to authorize your banking transactions and sensitive operations with OneAuth.',
                          style: OneAuthTheme.subHeadingStyle(context),
                        ),
                        const SizedBox(height: 24),
                        ..._authTypes.map((model) => _buildModelOption(model, isDark)),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: OneAuthPrimaryButton(
              label: _isSubmitting ? 'Updating...' : 'Update Auth Type',
              onPressed: (_isLoading || _selectedModelCode == null || _isSubmitting)
                  ? null
                  : _handleUpdateAuthType,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelOption(AuthenticationType model, bool isDark) {
    final isSelected = _selectedModelCode == model.code;
    final isCurrentActive = _currentActiveModelCode == model.code;
    final iconData = _getIconForCode(model.code);

    return GestureDetector(
      onTap: () => setState(() => _selectedModelCode = model.code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? (isSelected ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04))
              : (isSelected ? const Color(0xFFF0F7FF) : Colors.white),
          border: Border.all(
            color: isSelected
                ? OneAuthColors.secondaryBlue
                : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? OneAuthColors.primaryBlue
                    : (isDark ? Colors.grey[800] : Colors.grey[100]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey[300] : OneAuthColors.primaryBlue),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: OneAuthTheme.getPrimaryTextColor(context),
                          ),
                        ),
                      ),
                      if (isCurrentActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (model.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      model.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: OneAuthTheme.getSecondaryTextColor(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Radio<String>(
              value: model.code,
              groupValue: _selectedModelCode,
              activeColor: OneAuthColors.secondaryBlue,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedModelCode = val);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
