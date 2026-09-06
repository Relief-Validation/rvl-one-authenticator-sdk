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
    if (value.length > 1) {
      // Handle paste
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      final startIdx = digits.length >= widget.length ? 0 : index;
      for (var i = 0; i < digits.length && (startIdx + i) < widget.length; i++) {
        widget.controllers[startIdx + i].text = digits[i];
      }
      final nextIndex = (startIdx + digits.length).clamp(0, widget.length - 1);
      if (nextIndex < widget.length - 1) {
        widget.focusNodes[nextIndex].requestFocus();
      } else {
        widget.focusNodes[widget.length - 1].unfocus();
        if (widget.onFieldSubmitted != null) {
          widget.onFieldSubmitted!(
            widget.controllers.map((c) => c.text).join(),
            widget.length - 1,
          );
        }
      }
    } else if (value.length == 1) {
      if (index < widget.length - 1) {
        widget.focusNodes[index + 1].requestFocus();
      } else {
        widget.focusNodes[index].unfocus();
        if (widget.onFieldSubmitted != null) {
          widget.onFieldSubmitted!(
            widget.controllers.map((c) => c.text).join(),
            index,
          );
        }
      }
    } else if (value.isEmpty && index > 0) {
      widget.focusNodes[index - 1].requestFocus();
    }

    widget.onChanged(widget.controllers.map((c) => c.text).join());
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.length > 4;
    final boxWidth = isLong ? 42.0 : 50.0;
    final boxHeight = isLong ? 58.0 : 70.0;
    final spacing = isLong ? 8.0 : 12.0;
    final fontSize = isLong ? 20.0 : 24.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.length, (index) {
          return Row(
            children: [
              SizedBox(
                width: boxWidth,
                height: boxHeight,
                child: TextField(
                  controller: widget.controllers[index],
                  focusNode: widget.focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  obscureText: widget.obscureText,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: OneAuthTheme.getPrimaryTextColor(context),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
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
                      borderSide: const BorderSide(
                        color: OneAuthColors.primaryBlue,
                        width: 2,
                      ),
                    ),
                  ),
                  onChanged: (value) => _onChanged(value, index),
                ),
              ),
              if (index < widget.length - 1) SizedBox(width: spacing),
            ],
          );
        }),
      ),
    );
  }
}
