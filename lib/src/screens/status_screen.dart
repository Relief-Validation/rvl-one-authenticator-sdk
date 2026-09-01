import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/app_bar.dart';
import '../models/user.dart';
import '../widgets/primary_button.dart';
import 'status_view_model.dart';

class OneAuthStatusScreen extends StatefulWidget {
  final OneAuthUser user;
  final int currentStep; // 1, 2, or 3
  final VoidCallback? onComplete;

  const OneAuthStatusScreen({
    super.key,
    required this.user,
    this.currentStep = 2,
    this.onComplete,
  });

  @override
  State<OneAuthStatusScreen> createState() => _OneAuthStatusScreenState();
}

class _OneAuthStatusScreenState extends State<OneAuthStatusScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final OneAuthStatusViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = OneAuthStatusViewModel(user: widget.user, initialStep: widget.currentStep);
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _performEnrollmentSteps();
  }

  Future<void> _performEnrollmentSteps() async {
    final success = await _viewModel.performEnrollmentSteps();
    if (success) {
      if (_viewModel.isAlreadyValid) {
        // If already valid, we don't proceed to the next page (Verification)
        // We stay on this page to show the "Already Active" state and let the user go back.
        debugPrint('OneAuth: Device already enrolled, staying on status screen.');
      } else if (mounted && widget.onComplete != null) {
        widget.onComplete!();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_viewModel.errorMessage ?? 'Enrollment Failed')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final isDark = OneAuthTheme.isDarkMode(context);
        return Scaffold(
          backgroundColor: OneAuthTheme.getBackgroundColor(context),
          appBar: const OneAuthAppBar(),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF4F8FB),
                child: Column(
                  children: [
                    _buildStep(
                      step: 1,
                      title: 'Generating device signature',
                      isCompleted: _viewModel.currentStep > 1,
                      isActive: _viewModel.currentStep == 1,
                    ),
                    _buildDivider(isCompleted: _viewModel.currentStep > 1),
                    _buildStep(
                      step: 2,
                      title: 'Identity Verification',
                      isCompleted: _viewModel.currentStep > 2,
                      isActive: _viewModel.currentStep == 2,
                    ),
                    _buildDivider(isCompleted: _viewModel.currentStep > 2),
                    _buildStep(
                      step: 3,
                      title: 'Ready for Setup',
                      isCompleted: _viewModel.currentStep > 3,
                      isActive: _viewModel.currentStep == 3,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated Hourglass Icon or Success Icon
                      if (_viewModel.isAlreadyValid)
                        Icon(
                          Icons.check_circle_outline,
                          size: 100,
                          color: Colors.green[400],
                        )
                      else
                        RotationTransition(
                          turns: _controller,
                          child: Icon(
                            Icons.hourglass_empty,
                            size: 100,
                            color: Colors.cyan[400],
                          ),
                        ),
                      const SizedBox(height: 40),
                      Text(
                        _viewModel.isAlreadyValid 
                            ? 'OneAuth Already Active' 
                            : 'Checking your OneAuth status',
                        textAlign: TextAlign.center,
                        style: OneAuthTheme.headingStyle(context),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _viewModel.isAlreadyValid
                            ? 'Your device is already registered and secure.'
                            : 'Checking your mobile number and email against oneID\'s record',
                        textAlign: TextAlign.center,
                        style: OneAuthTheme.subHeadingStyle(context),
                      ),
                      if (_viewModel.isAlreadyValid) ...[
                        const SizedBox(height: 48),
                        OneAuthPrimaryButton(
                          label: 'Back to Home',
                          onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStep({
    required int step,
    required String title,
    required bool isCompleted,
    required bool isActive,
  }) {
    final isDark = OneAuthTheme.isDarkMode(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted 
                ? Colors.blueAccent 
                : (isActive ? (isDark ? Colors.grey[800] : Colors.white) : Colors.transparent),
            border: Border.all(
              color: isCompleted ? Colors.blueAccent : Colors.grey,
              width: 1,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    '$step',
                    style: TextStyle(
                      color: isActive 
                          ? (isDark ? Colors.white : Colors.black) 
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isActive || isCompleted ? FontWeight.bold : FontWeight.normal,
            color: isActive || isCompleted 
                ? OneAuthTheme.getPrimaryTextColor(context) 
                : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider({required bool isCompleted}) {
    return Container(
      margin: const EdgeInsets.only(left: 15.5),
      height: 20,
      width: 1,
      color: isCompleted ? Colors.blueAccent : Colors.grey[300],
    );
  }
}
