class OneAuthException implements Exception {
  final String message;
  final dynamic originalError;

  OneAuthException(this.message, [this.originalError]);

  @override
  String toString() => message;
}

class OneAuthAuthException extends OneAuthException {
  OneAuthAuthException(String message, [dynamic originalError])
      : super(message, originalError);
}

class OneAuthNetworkException extends OneAuthException {
  final int? statusCode;

  OneAuthNetworkException(String message, {this.statusCode, dynamic originalError})
      : super(message, originalError);
}

class OneAuthCryptoException extends OneAuthException {
  final String? code;

  OneAuthCryptoException(String message, {this.code, dynamic originalError})
      : super(message, originalError);
}

class OneAuthSessionException extends OneAuthException {
  OneAuthSessionException(String message, [dynamic originalError])
      : super(message, originalError);
}

class OneAuthValidationException extends OneAuthException {
  OneAuthValidationException(String message) : super(message);
}

class OneAuthSecurityException extends OneAuthException {
  OneAuthSecurityException(String message) : super(message);
}
