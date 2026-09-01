import 'package:flutter/material.dart';
import '../one_auth_impl.dart';
import '../core/exceptions.dart';

class OneAuthPinVerificationViewModel extends ChangeNotifier {
  final String txnId;
  final String txnHash;
  final String? numberMatchingCode;
  final int pinLength;

  bool _isLoading = false;
  String? _errorMessage;

  OneAuthPinVerificationViewModel({
    required this.txnId,
    required this.txnHash,
    this.numberMatchingCode,
    required this.pinLength,
  });

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  Future<bool> verifyPin(String pin) async {
    if (pin.length < pinLength) {
      _errorMessage = 'Please enter your $pinLength-digit PIN.';
      notifyListeners();
      return false;
    }

    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Re-initialize the SDK to ensure we have a fresh client token
      // In a real app, this might be handled globally, but here we follow existing logic
      await OneAuth().initialize(
        clientSecret: '9cca0a9dc2edc5bb3451f76b56a57a6c475f77b7242945a31471be',
      );
      
      await OneAuth().submitTransactionSignature(
        txnId: txnId,
        txnHash: txnHash,
        pin: pin,
        selectedNumberMatchingCode: numberMatchingCode,
      );
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on OneAuthException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
