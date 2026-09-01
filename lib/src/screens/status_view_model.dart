import 'package:flutter/material.dart';
import '../../one_auth.dart';
import '../one_auth_impl.dart';
import '../core/exceptions.dart';

class OneAuthStatusViewModel extends ChangeNotifier {
  final OneAuthUser user;
  final int initialStep;
  int _currentStep = 1;
  bool _isError = false;
  bool _isAlreadyValid = false;
  String? _errorMessage;

  OneAuthStatusViewModel({required this.user, this.initialStep = 1}) : _currentStep = initialStep;

  int get currentStep => _currentStep;
  bool get isError => _isError;
  bool get isAlreadyValid => _isAlreadyValid;
  String? get errorMessage => _errorMessage;

  Future<bool> performEnrollmentSteps() async {
    try {
      _isError = false;
      _errorMessage = null;
      _isAlreadyValid = false;

      // Preliminary check: Is the device already enrolled and valid?
      final status = await OneAuth().checkEnrollmentStatus();
      if (status['valid'] == true) {
        debugPrint('OneAuth: Device is already enrolled and valid.');
        _isAlreadyValid = true;
        _currentStep = 3;
        notifyListeners();
        return true; 
      }

      // If we are here, either it's not enrolled or not valid (e.g. revoked, not found)
      // For some reasons, we might want to throw an error instead of proceeding
      final reason = status['reason'];
      if (reason == 'ACCOUNT_LOCKED') {
        throw OneAuthException('Your account is locked. Please contact support.');
      }
      
      debugPrint('OneAuth: Proceeding with enrollment steps. Status reason: $reason');

      // Step 1: Fetch Nonce
      _currentStep = 1;
      notifyListeners();
      await OneAuth().getEnrollmentNonce(user.id);
      
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Verification (Simulated)
      _currentStep = 2;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 1));

      // Step 3: Ready for setup
      _currentStep = 3;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));

      return true;
    } on OneAuthException catch (e) {
      _isError = true;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _isError = true;
      _errorMessage = 'An unexpected error occurred: $e';
      notifyListeners();
      return false;
    }
  }
}
