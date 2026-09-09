import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/snack_bar.dart';
import '../one_auth_impl.dart';

/// Screen displayed when performing a transaction challenge requiring Push Approval or Number Matching verification.
class OneAuthPushVerificationScreen extends StatefulWidget {
  final String txnId;
  final String txnHash;
  final String? numberMatchingCode;
  final dynamic onComplete;

  const OneAuthPushVerificationScreen({
    super.key,
    required this.txnId,
    required this.txnHash,
    this.numberMatchingCode,
    required this.onComplete,
  });

  @override
  State<OneAuthPushVerificationScreen> createState() => _OneAuthPushVerificationScreenState();
}

class _OneAuthPushVerificationScreenState extends State<OneAuthPushVerificationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  bool _isVerifying = false;
  String? _currentNumberMatchingCode;
  List<String> _numberChoices = [];
  StreamSubscription? _pushSubscription;

  void _notifyComplete(bool success) {
    if (widget.onComplete is Function(bool)) {
      (widget.onComplete as Function(bool))(success);
    } else if (widget.onComplete is Function()) {
      (widget.onComplete as Function())();
    }
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

    _currentNumberMatchingCode = widget.numberMatchingCode;
    if (_currentNumberMatchingCode != null && _currentNumberMatchingCode!.isNotEmpty) {
      _updateNumberChoices(_currentNumberMatchingCode!);
    } else {
      final latestData = OneAuth().latestPushChallengeData;
      if (latestData != null) {
        final pushTxnId = latestData['txnId'];
        if (pushTxnId == widget.txnId || widget.txnId.isEmpty) {
          final pushCode = latestData['numberMatchingCode'] ?? latestData['number_matching_code'];
          if (pushCode != null) {
            _currentNumberMatchingCode = pushCode.toString();
            _updateNumberChoices(_currentNumberMatchingCode!);
          }
        }
      }
    }

    // Listen to FCM push challenge stream when incoming notification payload arrives
    _pushSubscription = OneAuth().onPushChallengeReceived.listen((data) {
      debugPrint('OneAuth PushVerificationScreen: Received FCM Challenge Data: $data');
      if (mounted) {
        final status = data['status']?.toString().toUpperCase();
        final userResp = data['userResponse']?.toString();
        if (status == 'VERIFIED' || status == 'SUCCESS' || status == 'APPROVED') {
          OneAuthSnackBar.show(context, message: 'Push Verification Approved!');
          _notifyComplete(true);
          return;
        } else if (status == 'DECLINED' || status == 'DENIED' || status == 'REJECTED' || status == 'FAILED' || userResp == 'false') {
          OneAuthSnackBar.show(context, message: 'Push Verification Denied.', isError: true);
          _notifyComplete(false);
          return;
        }

        final pushTxnId = data['txnId'];
        if (pushTxnId == widget.txnId || widget.txnId.isEmpty) {
          final pushCode = data['numberMatchingCode'] ?? data['number_matching_code'];
          final authType = data['authenticationType'] ?? data['authType'];

          if (pushCode != null || authType == 'NUMBER_MATCHING') {
            final codeStr = pushCode?.toString() ?? '42';
            setState(() {
              _currentNumberMatchingCode = codeStr;
              _updateNumberChoices(codeStr);
            });
          }
        }
      }
    });
  }

  void _updateNumberChoices(String codeStr) {
    final codeInt = int.tryParse(codeStr) ?? 42;
    final choice2 = ((codeInt + 17) % 150 + 10).toString();
    final choice3 = ((codeInt + 43) % 150 + 10).toString();
    _numberChoices = [codeStr, choice2, choice3]..shuffle();
  }

  @override
  void dispose() {
    _pushSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleVerificationSuccess([String? selectedNumber]) async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      await OneAuth().submitTransactionSignature(
        txnId: widget.txnId,
        txnHash: widget.txnHash,
        pin: selectedNumber ?? _currentNumberMatchingCode ?? 'PUSH_APPROVED',
        authType: _currentNumberMatchingCode != null ? 'NUMBER_MATCHING' : 'PUSH',
        selectedNumberMatchingCode: selectedNumber ?? _currentNumberMatchingCode,
      );

      if (mounted) {
        OneAuthSnackBar.show(context, message: 'Push Verification Approved!');
        _notifyComplete(true);
      }
    } catch (e) {
      if (mounted) {
        OneAuthSnackBar.show(
          context,
          message: 'Push Verification Failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Widget _buildNumberBox(String numStr) {
    final bool isTarget = numStr == _currentNumberMatchingCode;
    return GestureDetector(
      onTap: _isVerifying
          ? null
          : () {
              if (isTarget) {
                _handleVerificationSuccess(numStr);
              } else {
                OneAuthSnackBar.show(
                  context,
                  message: 'Incorrect number selected. Try again.',
                  isError: true,
                );
              }
            },
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
            numStr,
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
    final bool isMatching = _currentNumberMatchingCode != null;
    final String title = isMatching ? 'Number Matching Verification' : 'Push Approval Verification';
    final String description = isMatching
        ? 'Select the matching number shown below that corresponds to your notification banner to authorize.'
        : 'A notification has been sent to your registered device. Tap "Approve" on the push notification banner to authorize.';

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

                  if (isMatching && _currentNumberMatchingCode != null) ...[
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
                                Text('Verification Sent', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                                          ? 'Select matching number on screen'
                                          : 'Approve transaction challenge?',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
