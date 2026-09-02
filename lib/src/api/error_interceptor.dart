import 'package:dio/dio.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    String errorMessage;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        errorMessage = 'Connection timed out. Please check your internet connection and try again.';
        break;
      case DioExceptionType.badResponse:
        final data = err.response?.data;
        if (data is Map) {
          errorMessage = data['message'] ?? 
                         data['error'] ?? 
                         data['reason'] ?? 
                         'Server error: ${err.response?.statusCode}';
        } else {
          errorMessage = 'The server responded with an error (${err.response?.statusCode}).';
        }
        break;
      case DioExceptionType.cancel:
        errorMessage = 'The request was cancelled.';
        break;
      case DioExceptionType.connectionError:
        errorMessage = 'No internet connection detected. Please check your network settings.';
        break;
      case DioExceptionType.badCertificate:
        errorMessage = 'Secure connection failed. Please ensure your device clock is correct.';
        break;
      default:
        errorMessage = 'An unexpected network error occurred. Please try again later.';
    }

    // Create a new DioException with the friendly message as the error object
    final friendlyException = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: errorMessage,
      message: errorMessage,
    );

    return handler.next(friendlyException);
  }
}
