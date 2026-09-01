import 'package:flutter/material.dart';

class OneAuthColors {
  static const Color primaryBlue = Color(0xFF0D2842);
  static const Color secondaryBlue = Color(0xFF1B486D);
  static const Color errorRed = Color(0xFFD32F2F);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);
}

class OneAuthTheme {
  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color getBackgroundColor(BuildContext context) {
    return isDarkMode(context) ? OneAuthColors.surfaceDark : OneAuthColors.surfaceLight;
  }

  static Color getPrimaryTextColor(BuildContext context) {
    return isDarkMode(context) ? OneAuthColors.textPrimaryDark : OneAuthColors.textPrimaryLight;
  }

  static Color getSecondaryTextColor(BuildContext context) {
    return isDarkMode(context) ? OneAuthColors.textSecondaryDark : OneAuthColors.textSecondaryLight;
  }

  static Color getBorderColor(BuildContext context) {
    return isDarkMode(context) ? Colors.grey[800]! : Colors.grey[300]!;
  }

  static TextStyle headingStyle(BuildContext context) {
    return TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: getPrimaryTextColor(context),
    );
  }

  static TextStyle subHeadingStyle(BuildContext context) {
    return TextStyle(
      fontSize: 14,
      color: getSecondaryTextColor(context),
      height: 1.4,
    );
  }
}
