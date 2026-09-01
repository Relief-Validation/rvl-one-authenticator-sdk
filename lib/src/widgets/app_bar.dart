import 'package:flutter/material.dart';
import '../core/theme.dart';

class OneAuthAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;

  const OneAuthAppBar({
    super.key,
    this.title = 'OneAuth',
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [OneAuthColors.primaryBlue, OneAuthColors.secondaryBlue],
          ),
        ),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      centerTitle: centerTitle,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
