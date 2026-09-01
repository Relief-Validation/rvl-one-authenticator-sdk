# OneAuth SDK

Unified authentication and identity SDK for mobile applications, providing a secure infrastructure layer for multi-factor authentication (MFA) and client-level security.

## Core Principles

- **Infrastructure vs. Business**: OneAuth handles the security handshake and client-level authentication, while your application manages business-specific user data and logic.
- **Client Handshake**: Automatically authenticates your mobile app instance with the identity server using `clientSecret` and dynamic `appPackageId`.
- **Pre-Authenticated Networking**: Provides a pre-configured `Dio` client that automatically injects `X-Client-Token` into every request.
- **Secure Persistence**: Uses `flutter_secure_storage` to ensure all sensitive data (TOTP secrets, tokens) is encrypted at rest.

## Features

- **Automated Client Auth**: Seamlessly fetches and manages client-level tokens.
- **Modern MFA Screens**: Ready-to-use flows for Biometrics, PIN, TOTP, and Push Approval.
- **Secure Configuration**: Powered by `envied` with obfuscated secrets to prevent reverse-engineering of sensitive keys.
- **Response Caching**: Integrated `dio_cache_interceptor` for optimized performance and offline resilience.
- **Branded UI**: Professional Material 3 components with glassmorphism and signature gradients.

## Installation

Add the following to your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  one_auth:
    git:
      url: https://github.com/Relief-Validation/rvl-one-authenticator-sdk.git
      ref: v0.1.0
```

Or for SSH:
```yaml
dependencies:
  one_auth:
    git:
      url: git@github.com:Relief-Validation/rvl-one-authenticator-sdk.git
      ref: v0.1.0
```

## Configuration

1. Create a `.env` file in the `packages/one_auth` directory:
   ```env
   BASE_URL=http://your-api-url.com/api/v1
   ```
2. Generate the environment classes:
   ```bash
   cd packages/one_auth
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

## Usage

### 1. Initialization (Client Handshake)

Initialize the SDK, typically on-demand or during app startup. You can also listen to the authentication status:

```dart
import 'package:one_auth/one_auth.dart';

final auth = OneAuth();

// Listen to client auth status
auth.onClientStatusChanged.listen((isAuthenticated) {
  print('OneAuth SDK is authenticated: $isAuthenticated');
});

// This performs the client authentication flow automatically
await auth.initialize(
  clientSecret: 'your_client_secret',
); 
```

### 2. Using the Authenticated Dio Client

Use the SDK's `dio` instance to communicate with your backend. It automatically includes all necessary security headers.

```dart
final dio = OneAuth().dio;

// This request will automatically have 'X-Client-Token' in headers
final response = await dio.post('/your-app-endpoint/login', data: {...});
```

### 3. Enrollment Orchestration

The `enroll` method simplifies the entire registration process by handling nonce retrieval, hardware key generation, CSR submission, and local persistence in a single call.

```dart
final auth = OneAuth();
final user = OneAuthUser(
  accountNumber: '123456789',
  name: 'John Doe',
  nid: '1990123456789',
  dob: '1990-01-01',
  phoneNumber: '+8801700000000',
  email: 'john.doe@example.com',
);

try {
  final result = await auth.enroll(user);
  print('Enrollment successful: ${result['authenticatorUserId']}');
} catch (e) {
  print('Enrollment failed: $e');
}
```

### 4. Integrated MFA Screens

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => OneAuthSetupScreen(
      user: oneAuthUser,
      onConfirm: () => _proceedToVerification(context),
      onCancel: () => Navigator.pop(context),
    ),
  ),
);
```

## Security Requirements

- **Android**: Ensure your `MainActivity` extends `FlutterFragmentActivity` for biometric support.
- **iOS**: Add `NSFaceIDUsageDescription` to your `Info.plist`.
- **Environment**: Never check in the generated `env.g.dart` if it contains sensitive keys (though OneAuth obfuscates them).

## Dependencies

- **Networking**: `dio`, `dio_cache_interceptor`
- **Security**: `flutter_secure_storage`, `local_auth`, `envied`
- **Metadata**: `package_info_plus`
