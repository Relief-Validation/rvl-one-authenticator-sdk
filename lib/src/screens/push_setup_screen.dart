import 'package:flutter/material.dart';
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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMatching = widget.type == PushSetupType.matching;
    final String title = isMatching ? 'Number Matching' : 'Push Approval';
    final String description = isMatching
        ? 'You will receive a notification and must select the matching number shown on your login screen to approve.'
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
                                Icon(Icons.lock_outline, size: 40, color: Colors.grey),
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
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
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
                                          decoration: const BoxDecoration(color: OneAuthColors.primaryBlue, shape: BoxShape.circle),
                                          child: const Center(child: Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('OneAuth', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        const Spacer(),
                                        const Text('now', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      isMatching ? 'Match the number: 42' : 'Approve login request?',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 12),
                                    if (isMatching)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [42, 17, 85].map((n) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: n == 42 ? OneAuthColors.primaryBlue : Colors.grey[300]!),
                                            borderRadius: BorderRadius.circular(4),
                                            color: n == 42 ? OneAuthColors.primaryBlue.withValues(alpha: 0.1) : null,
                                          ),
                                          child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: n == 42 ? OneAuthColors.primaryBlue : Colors.black)),
                                        )).toList(),
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
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: OneAuthPrimaryButton(
              label: 'Activate $title',
              onPressed: () async {
                try {
                  await OneAuth().submitCsr(
                    widget.user.copyWith(
                      preferredAuthenticationType: widget.type == PushSetupType.matching
                          ? 'NUMBER_MATCHING'
                          : 'PUSH',
                    ),
                  );
                  widget.onComplete();
                } catch (e) {
                  OneAuthSnackBar.show(
                    context,
                    message: 'Activation Failed: $e',
                    isError: true,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
