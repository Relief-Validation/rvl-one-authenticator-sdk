import 'package:flutter/material.dart';
import '../core/theme.dart';

class OneAuthSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const OneAuthSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = OneAuthTheme.isDarkMode(context);
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? OneAuthColors.textPrimaryDark : OneAuthColors.primaryBlue,
          side: BorderSide(
            color: isDark ? OneAuthColors.textSecondaryDark : OneAuthColors.primaryBlue,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
