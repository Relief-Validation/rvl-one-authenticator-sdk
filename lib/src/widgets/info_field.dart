import 'package:flutter/material.dart';
import '../core/theme.dart';

class OneAuthInfoField extends StatelessWidget {
  final String label;
  final String value;

  const OneAuthInfoField({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = OneAuthTheme.isDarkMode(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: OneAuthTheme.getSecondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: OneAuthTheme.getBorderColor(context),
              ),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: OneAuthTheme.getPrimaryTextColor(context),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
