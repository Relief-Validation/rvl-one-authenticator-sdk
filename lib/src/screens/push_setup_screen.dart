import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_bar.dart';
import '../models/user.dart';
import '../one_auth_impl.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../widgets/snack_bar.dart';

enum PushSetupType { approval, matching }

class OneAuthPushSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final Function onComplete;
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
  List<String> _numberChoices = ['108', '042', '085'];
  StreamSubscription? _pushSubscription;

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

  void _updateNumberChoices(dynamic pushCode) {
    final codeStr = formatNumberMatchingCode(pushCode) ?? '108';
    final codeInt = int.tryParse(codeStr) ?? 108;
    final targetLen = codeStr.isNotEmpty ? codeStr.length : 3;
    final choice2 = ((codeInt + 17) % 150 + 10).toString().padLeft(targetLen, '0');
    final choice3 = ((codeInt + 43) % 150 + 10).toString().padLeft(targetLen, '0');
    _numberChoices = [codeStr, choice2, choice3]..shuffle();
  }

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

    // Check if a push challenge payload was already received before screen mounted
    final latestData = OneAuth().latestPushChallengeData;
    if (latestData != null) {
      _messageId = latestData['messageId'] ?? latestData['message_id'] ?? latestData['customerUniqueKey'];
      final pushCode = latestData['numberMatchingCode'] ?? latestData['number_matching_code'];
      if (pushCode != null) {
        _updateNumberChoices(pushCode);
      }
    }

    // Listen for incoming FCM push challenge details
    _pushSubscription = OneAuth().onPushChallengeReceived.listen((data) {
      debugPrint('OneAuth PushSetupScreen: Received Push Data: $data');
      if (mounted) {
        final status = data['status']?.toString().toUpperCase();
        final userResp = data['userResponse']?.toString();
        if (status == 'VERIFIED' || status == 'SUCCESS' || status == 'APPROVED') {
          OneAuthSnackBar.show(context, message: 'Push Approval Verified!');
          _notifyComplete(true);
          return;
        } else if (status == 'DECLINED' || status == 'DENIED' || status == 'REJECTED' || status == 'FAILED' || userResp == 'false') {
          OneAuthSnackBar.show(context, message: 'Push Approval Denied.', isError: true);
          _notifyComplete(false);
          return;
        }

        setState(() {
          _messageId = data['messageId'] ?? data['message_id'] ?? data['customerUniqueKey'];
          final pushCode = data['numberMatchingCode'] ?? data['number_matching_code'];
          if (pushCode != null) {
            _updateNumberChoices(pushCode);
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
      debugPrint('OneAuth: submitCsr completed on load. Awaiting push notification approval...');
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

  Future<void> _verifySelectedNumber(String selectedNumber) async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      await OneAuth().verifyNumberMatching(
        selectedNumber: selectedNumber,
        messageId: _messageId,
        preferredAuthenticationType: widget.type == PushSetupType.matching
            ? 'NUMBER_MATCHING'
            : 'PUSH',
      );

      if (mounted) {
        OneAuthSnackBar.show(context, message: 'Number Matching Verified ($selectedNumber)!');
        _notifyComplete(true);
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

  Widget _buildNumberBox(String n) {
    return GestureDetector(
      onTap: _isVerifying ? null : () => _verifySelectedNumber(n),
      child: Container(
        width: 72,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF1E293B),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            n,
            style: const TextStyle(
              fontSize: 22,
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
    final String title = isMatching ? 'Number Matching Setup' : 'Push Approval Setup';
    final String description = isMatching
        ? 'Tap the matching number below that corresponds to your notification banner to verify.'
        : 'You will receive a notification with "Approve" or "Deny" buttons on your device. Respond to the notification to authorize.';

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
                    textAlign: TextAlign.center,
                    style: OneAuthTheme.headingStyle(context),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: OneAuthTheme.subHeadingStyle(context),
                  ),
                  const SizedBox(height: 30),

                  if (isMatching) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: OneAuthColors.primaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OneAuthColors.primaryBlue, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'MATCHING NUMBERS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: OneAuthColors.primaryBlue,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _isVerifying
                              ? const SizedBox(
                                  height: 48,
                                  child: Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: _numberChoices.map((n) => _buildNumberBox(n)).toList(),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // Mock Animated Phone Display
                  Center(
                    child: Container(
                      width: 240,
                      height: 300,
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
                          const Positioned(
                            top: 40,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                Text('Push Notification', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),

                          // Sliding Notification Mockup
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
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                            color: OneAuthColors.primaryBlue,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.security, color: Colors.white, size: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('OneAuth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                        const Spacer(),
                                        const Text('now', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isMatching
                                          ? 'Tap matching number in app'
                                          : 'Approve push request?',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    if (!isMatching) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'NO',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: OneAuthColors.primaryBlue,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'YES',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
