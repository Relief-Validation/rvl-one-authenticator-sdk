import 'dart:async';
import 'package:flutter/material.dart';
import '../core/secure_id_manager.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../models/user.dart';
import '../one_auth_impl.dart';
import '../core/theme.dart';
import '../widgets/snack_bar.dart';

enum PushSetupType { approval, matching }

class OneAuthPushSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback onComplete;
  final PushSetupType type;

  const OneAuthPushSetupScreen({
    super.key,
    required this.user,
    required this.onComplete,
    required this.type,
  });

  @override
  State<OneAuthPushSetupScreen> createState() => _OneAuthPushSetupScreenState();
}

class _OneAuthPushSetupScreenState extends State<OneAuthPushSetupScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  bool _isSubmitting = false;
  bool _isVerifying = false;
  String? _messageId;
  List<int> _numberChoices = [108, 42, 85];
  StreamSubscription? _pushSubscription;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: const Offset(0, 0.2),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    // Listen for incoming FCM push challenge details
    _pushSubscription = OneAuth().onPushChallengeReceived.listen((data) {
      debugPrint('OneAuth PushSetupScreen: Received Push Data: $data');
      if (mounted) {
        setState(() {
          _messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
          if (data['numberMatchingCode'] != null) {
            final code = int.tryParse(data['numberMatchingCode'].toString()) ?? 108;
            final choice2 = (code + 17) % 150 + 10;
            final choice3 = (code + 43) % 150 + 10;
            _numberChoices = [code, choice2, choice3];
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _submitCsr();
    });
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitCsr() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await OneAuth().submitCsr(
        widget.user.copyWith(
          preferredAuthenticationType: widget.type == PushSetupType.matching
              ? 'NUMBER_MATCHING'
              : 'PUSH',
        ),
      );
      debugPrint('OneAuth: submitCsr completed automatically on load.');
    } catch (e) {
      debugPrint('OneAuth: submitCsr failed: $e');
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Activation Failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _verifySelectedNumber(int selectedNumber) async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final deviceUuid = await OneAuthSecureIdManager.getOrCreateDeviceUuid();
      final fcmToken = await OneAuth().getOrCreateFcmToken();

      final payload = <String, dynamic>{
        "messageId": _messageId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        "deviceUuid": deviceUuid,
        "fcmToken": fcmToken,
        "preferredAuthenticationType": "NUMBER_MATCHING",
        "number": selectedNumber.toString(),
      };

      debugPrint('OneAuth: Calling /verify with payload: $payload');

      final response = await OneAuth().dio.post(
        '/enrollment/verify',
        data: payload,
      );

      debugPrint('OneAuth: /verify response: ${response.data}');

      if (response.data is Map<String, dynamic>) {
        await OneAuth().persistEnrollmentResult(response.data as Map<String, dynamic>);
      }

      if (mounted) {
        OneAuthSnackBar.show(context, message: 'Number Matching Verified ($selectedNumber)!');
        widget.onComplete();
      }
    } catch (e) {
      debugPrint('OneAuth: /verify failed: $e');
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Verification Failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Widget _buildNumberBox(int n) {
    return GestureDetector(
      onTap: _isVerifying ? null : () => _verifySelectedNumber(n),
      child: Container(
        width: 60,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEF5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF1E293B),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            '$n',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMatching = widget.type == PushSetupType.matching;
    final String title = isMatching ? 'Number Matching' : 'Push Approval';
    final String description = isMatching
        ? 'Tap the matching number below that corresponds to your notification banner to verify.'
        : 'You will receive a notification with "Approve" or "Deny" buttons on your screen to authorize requests.';

    return Scaffold(
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      appBar: const OneAuthAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Text(
                    title,
                    style: OneAuthTheme.headingStyle(context),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: OneAuthTheme.subHeadingStyle(context),
                  ),
                  const SizedBox(height: 40),
                  
                  // Animation Area
                  Center(
                    child: Container(
                      width: 240,
                      height: 380,
                      decoration: BoxDecoration(
                        color: OneAuthTheme.isDarkMode(context) ? Colors.grey[900] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: OneAuthTheme.isDarkMode(context) ? Colors.grey[800]! : Colors.grey[400]!, 
                          width: 4,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Mock Phone Screen Content
                          const Positioned(
                            top: 40,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                Icon(Icons.shield_outlined, size: 40, color: Colors.grey),
                                SizedBox(height: 10),
                                Text('10:45', style: TextStyle(fontSize: 48, color: Colors.grey, fontWeight: FontWeight.w300)),
                                Text('Monday, August 18', style: TextStyle(fontSize: 14, color: Colors.grey)),
                              ],
                            ),
                          ),
                          
                          // Sliding Notification
                          SlideTransition(
                            position: _slideAnimation,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: const BoxDecoration(
                                            color: OneAuthColors.primaryBlue,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('OneAuth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        const Spacer(),
                                        const Text('now', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isMatching
                                          ? 'Tap the matching number:'
                                          : 'Approve login request?',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 12),

                                    // Number Matching Options styled like design
                                    if (isMatching)
                                      _isVerifying
                                          ? const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                              children: _numberChoices.map((n) => _buildNumberBox(n)).toList(),
                                            )
                                    else
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text('Deny', style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 16),
                                          const Text('Approve', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Show bottom button ONLY for standard Push Approval (not for Number Matching)
          if (!isMatching)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: OneAuthPrimaryButton(
                label: _isSubmitting ? 'Activating Push Approval...' : 'Continue',
                onPressed: _isSubmitting ? null : () => widget.onComplete(),
              ),
            ),
        ],
      ),
    );
  }
}
