import 'package:flutter/material.dart';
import '../models/user.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/info_field.dart';
import '../widgets/secondary_button.dart';

class OneAuthSetupScreen extends StatefulWidget {
  final OneAuthUser user;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const OneAuthSetupScreen({
    super.key,
    required this.user,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<OneAuthSetupScreen> createState() => _OneAuthSetupScreenState();
}

class _OneAuthSetupScreenState extends State<OneAuthSetupScreen> {
  bool _consented = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OneAuthTheme.getBackgroundColor(context),
      appBar: const OneAuthAppBar(),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set up OneAuth',
                              style: OneAuthTheme.headingStyle(context),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'OneAuth will use the details already on your Alo Bank profile to verify your identity with OneID. Nothing is shared untill you approve below.',
                              style: OneAuthTheme.subHeadingStyle(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: widget.user.profileImageUrl != null 
                            ? NetworkImage(widget.user.profileImageUrl!) 
                            : null,
                        child: widget.user.profileImageUrl == null 
                            ? const Icon(Icons.person, size: 40) 
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OneAuthInfoField(label: 'Full Name', value: widget.user.name),
                  OneAuthInfoField(label: 'Mobile Number', value: widget.user.phoneNumber ?? ''),
                  OneAuthInfoField(label: 'Email', value: widget.user.email),
                  OneAuthInfoField(label: 'NID', value: widget.user.nid ?? ''),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: OneAuthTheme.isDarkMode(context)
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF0F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _consented,
                            onChanged: (val) => setState(() => _consented = val ?? false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'I consent to sharing my name, mobile number, email, profile photo and identity document (NID/Passport) from my Alo Bank profile with OneID, to verify my identity and enable OneAuth.',
                            style: TextStyle(
                              fontSize: 12,
                              color: OneAuthTheme.getPrimaryTextColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OneAuthPrimaryButton(
                  label: 'Confirm and continue',
                  onPressed: widget.onConfirm,
                  isEnabled: _consented,
                ),
                const SizedBox(height: 12),
                OneAuthSecondaryButton(
                  label: 'Not Now',
                  onPressed: widget.onCancel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
