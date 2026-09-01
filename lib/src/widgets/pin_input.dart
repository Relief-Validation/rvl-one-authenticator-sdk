import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';

class OneAuthPinInput extends StatefulWidget {
  final int length;
  final Function(String) onChanged;
  final bool obscureText;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final Function(String, int)? onFieldSubmitted;

  const OneAuthPinInput({
    super.key,
    required this.length,
    required this.onChanged,
    required this.controllers,
    required this.focusNodes,
    this.obscureText = true,
    this.onFieldSubmitted,
  });

  @override
  State<OneAuthPinInput> createState() => _OneAuthPinInputState();
}

class _OneAuthPinInputState extends State<OneAuthPinInput> {
  void _onChanged(String value, int index) {
    if (value.length == 1) {
      if (index < widget.length - 1) {
        widget.focusNodes[index + 1].requestFocus();
      } else {
        widget.focusNodes[index].unfocus();
        if (widget.onFieldSubmitted != null) {
          widget.onFieldSubmitted!(widget.controllers.map((c) => c.text).join(), index);
        }
      }
    } else if (value.isEmpty && index > 0) {
      widget.focusNodes[index - 1].requestFocus();
    }
    
    widget.onChanged(widget.controllers.map((c) => c.text).join());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Row(
          children: [
            SizedBox(
              width: 50,
              height: 70,
              child: TextField(
                controller: widget.controllers[index],
                focusNode: widget.focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                obscureText: widget.obscureText,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: OneAuthTheme.getPrimaryTextColor(context),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: OneAuthTheme.getBorderColor(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: OneAuthColors.primaryBlue, width: 2),
                  ),
                ),
                onChanged: (value) => _onChanged(value, index),
              ),
            ),
            if (index < widget.length - 1) const SizedBox(width: 12),
          ],
        );
      }),
    );
  }
}
