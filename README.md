# OneAuth SDK

Unified authentication and identity SDK for mobile applications, providing a secure infrastructure layer for multi-factor authentication (MFA), hardware-backed transaction signing, and client-level security.

---

## Core Principles

- **Infrastructure vs. Business**: OneAuth manages the cryptographic handshake, device key generation, and client-level authentication, while your application manages business-specific user data and logic.
- **Client Handshake**: Automatically authenticates your mobile app instance with the identity server using `clientSecret` and dynamic `appPackageId`.
- **Pre-Authenticated Networking**: Provides a pre-configured `Dio` client that automatically injects `X-Client-Token` into every request.
- **Hardware-Backed Security**: Generates and stores cryptographic keys inside the device's Secure Enclave / TEE for hardware-level transaction signing.
- **Secure Persistence**: Uses `flutter_secure_storage` to ensure all sensitive data (TOTP secrets, tokens) is encrypted at rest.

---

## Features

- **Automated Client Auth**: Seamlessly fetches and manages client-level tokens.
- **Ready-to-Use MFA Flows**: Pre-built screens for Biometrics, PIN, TOTP, and Push Approval.
- **Hardware Transaction Signing**: Signs transaction challenge hashes with hardware-backed private keys.
- **Runtime Threat Detection**: Proactive monitoring for Root/Jailbreak, Emulators, and Hooking (Frida) via **freeRASP**.
- **Secure Configuration**: Obfuscated secrets powered by **Envied** to prevent reverse engineering.
- **Response Caching**: Integrated `dio_cache_interceptor` for optimized performance and offline resilience.
- **Branded UI**: Professional Material 3 components with glassmorphism and signature gradients.

---

## Installation

Add the following to your Flutter app's `pubspec.yaml`:

### Via Git Repository (HTTPS)
```yaml
dependencies:
  one_auth:
    git:
      url: https://github.com/Relief-Validation/rvl-one-authenticator-sdk.git
      ref: v0.1.0
```

### Via Git Repository (SSH)
```yaml
dependencies:
  one_auth:
    git:
      url: git@github.com:Relief-Validation/rvl-one-authenticator-sdk.git
      ref: v0.1.0
```

### Local Path (Monorepo)
```yaml
dependencies:
  one_auth:
    path: packages/one_auth
```

---

## Platform Setup

### Android
1. In `android/app/src/main/kotlin/.../MainActivity.kt`, ensure `MainActivity` extends `FlutterFragmentActivity` to support biometric authentication:
   ```kotlin
   import io.flutter.embedding.android.FlutterFragmentActivity

   class MainActivity: FlutterFragmentActivity()
   ```

2. Ensure your `minSdkVersion` in `android/app/build.gradle` is at least `23`.

### iOS
Add `NSFaceIDUsageDescription` to your `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>We use biometric authentication to securely authorize transactions and verify your identity.</string>
```

---

## SDK Initialization & Client Handshake

Initialize the SDK, typically during app startup or before launching authentication features.

```dart
import 'package:one_auth/one_auth.dart';

final auth = OneAuth();

// Optional: Listen to client auth status changes
auth.onClientStatusChanged.listen((isAuthenticated) {
  print('OneAuth SDK is authenticated: $isAuthenticated');
});

// Perform the client-level handshake with the security server
await auth.initialize(
  clientSecret: 'YOUR_CLIENT_SECRET',
);
```

---

## User Data & Setup Screen

The `OneAuthSetupScreen` requires a `OneAuthUser` object as a payload. This object carries the user's identity and banking details to the OneAuth orchestration layer.

### `OneAuthUser` Model

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `String` (Required) | The unique identifier of the user in the bank's system. |
| `name` | `String` (Required) | Full name of the user. |
| `email` | `String` (Required) | Email address. |
| `phoneNumber` | `String?` | Mobile phone number. |
| `nid` | `String?` | National ID number for verification. |
| `dob` | `String?` | Date of birth (format: `YYYY-MM-DD`). |
| `accountNumber` | `String?` | Primary bank account number. |
| `profileImageUrl` | `String?` | URL for the user's profile picture. |
| `preferredAuthenticationType` | `String?` | Set by the SDK during enrollment (e.g. `'PIN'`, `'BIOMETRIC'`). |

### Passing Data to Setup Screen

```dart
final oneAuthUser = OneAuthUser(
  id: user.id,
  name: user.name,
  email: user.email,
  phoneNumber: user.phoneNumber,
  nid: '601 447 3331',
  accountNumber: '1234567890',
  dob: '1990-01-01',
);

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => OneAuthSetupScreen(
      user: oneAuthUser,
      onConfirm: () {
        // Proceed to OneAuthStatusScreen
      },
      onCancel: () => Navigator.pop(context),
    ),
  ),
);
```

---

## Activation Flow (MFA Enrollment)

The activation process is orchestrated using pre-built UI components from the SDK:

1. **Setup Screen (`OneAuthSetupScreen`)**: Presented to the user for consent and data confirmation (NID, Account Number, etc.).
2. **Status Screen (`OneAuthStatusScreen`)**: Orchestrates the background registration stages:
   - **Step 1**: Generating device signature (Hardware Key generation in TEE/Enclave).
   - **Step 2**: Identity Verification (Nonce fetch & CSR Handshake).
   - **Step 3**: Finalizing Security Profile.
3. **Verification Method Selection (`OneAuthVerificationModelScreen`)**: Allows the user to select and set up their preferred authentication method (PIN, Biometrics, TOTP).
4. **Completion (`OneAuthSnackBar`)**: Provides immediate visual feedback upon successful activation.

---

## Transaction Signing (Transfer Flow)

High-value operations (e.g., money transfers) require hardware-backed digital signatures.

> [!IMPORTANT]
> Always call `await OneAuth().initialize(clientSecret: '...')` before initiating the signing session to ensure the client security token is valid.

### Step-by-Step Signing Flow

1. **Initialize SDK**: Ensure client session is active.
2. **Challenge Generation**: Request a signing challenge from your Core Banking System (CBS) / backend API.

#### Challenge Payload Example (Sent to CBS Backend)
| Field | Description |
| :--- | :--- |
| `bankTxnId` | Unique transaction reference from the bank system. |
| `customerUniqueKey` | The persistent Authenticator User ID. |
| `fromAccount` | Source account number. |
| `toAccount` | Destination account number. |
| `amount` | Transaction amount. |
| `currency` | Currency code (e.g. `'BDT'`). |

#### Challenge Response Parameters (Received from Backend)
| Field | Description |
| :--- | :--- |
| `txnId` | Internal SDK transaction ID. |
| `txnHash` | SHA-256 hash of the transaction data to be signed. |
| `authenticationType` | Requested verification method (e.g., `'PIN'`, `'BIOMETRIC'`). |
| `numberMatchingCodeForDisplay` | (Optional) 2-digit code for Number Matching / Push flows. |

#### Launching the Verification UI

```dart
final challengeResult = await apiService.initChallenge(...);

final txnId = challengeResult['txnId'];
final txnHash = challengeResult['txnHash'];
final authType = challengeResult['authenticationType'];
final numberMatchingCode = challengeResult['numberMatchingCodeForDisplay'];

if (txnId != null && txnHash != null) {
  // 1. Ensure SDK session is initialized
  await OneAuth().initialize(clientSecret: 'YOUR_CLIENT_SECRET');

  // 2. Launch SDK Verification Screen based on authType
  bool? verified;
  if (authType == 'PIN') {
    verified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OneAuthPinVerificationScreen(
          txnId: txnId,
          txnHash: txnHash,
          numberMatchingCode: numberMatchingCode,
          pinLength: 4, // Optional: defaults to 4
          onComplete: () => Navigator.pop(context, true),
        ),
      ),
    );
  }

  // 3. Handle verification result
  if (verified != true) {
    // Transaction rejected or cancelled
    return;
  }

  // 4. Submit transaction to banking backend
  await apiService.executeTransfer(...);
}
```

3. **Hardware Signing**: The SDK uses the Secure Enclave / TEE to sign `txnHash` with the private key.
4. **Execution**: Upon verification, proceed to execute the transfer on your banking backend.

---

## Pre-Authenticated Dio Networking

Use the SDK's built-in `dio` client to make authenticated calls to your backend services:

```dart
final dio = OneAuth().dio;

// Automatically includes 'X-Client-Token' and configured interceptors
final response = await dio.post('/your-endpoint', data: {
  'key': 'value',
});
```

---

## Security Features

- **Runtime Threat Detection**: Integrates **freeRASP** to detect root/jailbreak, debuggers, emulators, and dynamic instrumentation hooks (Frida).
- **Environment Obfuscation**: Secure secrets and base URLs are compiled and obfuscated via **Envied**.
- **Exception Handling**: Typed security exceptions (`OneAuthSecurityException`, `OneAuthCryptoException`) allow fine-grained error handling.

---

## Dependencies

- **Networking**: `dio`, `dio_cache_interceptor`
- **Security**: `flutter_secure_storage`, `local_auth`, `freerasp`, `crypto`, `envied`
- **Device Info**: `device_info_plus`, `package_info_plus`
