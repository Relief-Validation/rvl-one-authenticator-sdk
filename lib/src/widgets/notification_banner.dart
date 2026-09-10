import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import 'snack_bar.dart';

/// Reusable banner for simulated push notifications containing TOTP codes.
class OneAuthNotificationBanner extends StatelessWidget {
  final String code;
  final VoidCallback onDismiss;
  final String title;

  const OneAuthNotificationBanner({
    super.key,
    required this.code,
    required this.onDismiss,
    this.title = 'One Authenticator',
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
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
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: OneAuthColors.primaryBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Your TOTP code is: $code',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: OneAuthColors.primaryBlue, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  onDismiss();
                  OneAuthSnackBar.show(
                    context,
                    message: 'Code copied to clipboard',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
