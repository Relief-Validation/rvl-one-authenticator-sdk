import 'package:flutter/material.dart';
import '../core/theme.dart';

class OneAuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isEnabled;

  const OneAuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          gradient: isEnabled && onPressed != null
              ? const RadialGradient(
                  center: Alignment.center,
                  radius: 8.0,
                  colors: [OneAuthColors.secondaryBlue, OneAuthColors.primaryBlue],
                )
              : null,
          color: (isEnabled && onPressed != null)
              ? null
              : (OneAuthTheme.isDarkMode(context)
                  ? OneAuthColors.primaryBlue.withValues(alpha: 0.3)
                  : OneAuthColors.primaryBlue.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          onPressed: isEnabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
