import 'package:flutter/material.dart';
import '../one_auth_impl.dart';
import '../models/user.dart';
import '../core/exceptions.dart';

class OneAuthPinSetupViewModel extends ChangeNotifier {
  final OneAuthUser user;
  final int pinLength;
  
  bool _isLoading = false;
  String? _errorMessage;

  OneAuthPinSetupViewModel({required this.user, required this.pinLength});

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<bool> setupPin(String pin, String confirmPin) async {
    try {
      if (pin.length < pinLength || confirmPin.length < pinLength) {
        _errorMessage = 'Please enter a $pinLength-digit PIN in both sections.';
        notifyListeners();
        return false;
      }

      if (pin != confirmPin) {
        _errorMessage = 'PINs do not match. Please try again.';
        notifyListeners();
        return false;
      }

      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final userWithPin = user.copyWith(
        pin: pin,
        preferredAuthenticationType: 'PIN',
      );
      await OneAuth().submitCsr(userWithPin);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on OneAuthException catch (e) {
      debugPrint('OneAuth Exception during PIN setup: $e');
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('Unexpected error during PIN setup: $e');
      _errorMessage = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
