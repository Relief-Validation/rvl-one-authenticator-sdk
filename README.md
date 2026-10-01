# OneAuth SDK

Unified authentication and identity SDK for mobile applications, providing a secure infrastructure layer for multi-factor authentication (MFA), hardware-backed transaction signing, and client-level security.

---

## Core Principles

- **Infrastructure vs. Business**: OneAuth manages the cryptographic handshake, device key generation, and client-level authentication, while your application manages business-specific user data and logic.
- **Hardware-Backed Security**: Generates and stores cryptographic keys inside the device's Secure Enclave / TEE for hardware-level transaction signing.
- **Canonical Payload Hashing**: Computes deterministic SHA-256 hashes (`TransactionHashService`) across canonical JSON representations for transaction integrity (`X-SIGNATURE`).
- **Secure Persistence**: Uses `flutter_secure_storage` to ensure all sensitive data (TOTP secrets, certificates, tokens) is encrypted at rest.

---

## Features

- **Ready-to-Use MFA Flows**: High-level orchestration via `startEnrollmentFlow` and `verifyTransaction`.
- **Transaction Hash Service**: Built-in canonical JSON serialization and SHA-256 computation (`TransactionHashService`).
- **Hardware Transaction Signing**: Signs transaction challenge hashes with hardware-backed private keys in the TEE/Secure Enclave.
- **Runtime Threat Detection**: Proactive monitoring for Root/Jailbreak, Emulators, and Hooking (Frida) via **freeRASP**.
- **Branded UI**: Professional Material 3 components for Biometrics, PIN, TOTP, and Push Approval.

---

## Requirements & Compatibility

| Environment | Supported Versions |
| :--- | :--- |
| **Dart SDK** | `>= 3.0.0 < 4.0.0` |
| **Flutter** | `>= 3.0.0` |
| **Android** | `minSdkVersion 23` (Android 6.0+) |
| **iOS** | `iOS 12.0+` |

---

## Installation

Add the following to your Flutter app's `pubspec.yaml`:

### Via Git Repository (HTTPS)
```yaml
dependencies:
  one_auth:
    git:
      url: https://github.com/Relief-Validation/rvl-one-authenticator-sdk.git
      ref: v0.6.0
```

### Via Local Path (Monorepo)
```yaml
dependencies:
  one_auth:
    path: packages/one_auth
```

---

## Platform Setup

### Android
1. Add the required permissions to `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   ```

2. In `android/app/src/main/kotlin/.../MainActivity.kt`, ensure `MainActivity` extends `FlutterFragmentActivity`:
   ```kotlin
   import io.flutter.embedding.android.FlutterFragmentActivity

   class MainActivity: FlutterFragmentActivity()
   ```

3. Ensure `minSdkVersion` in `android/app/build.gradle` is at least `23`.

### iOS
Add `NSFaceIDUsageDescription` to your `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>We use biometric authentication to securely authorize transactions and verify your identity.</string>
```

---

## MFA Enrollment Flow (`startEnrollmentFlow`)

Pass the user data and optional auth token to launch the complete pre-built enrollment UI sequence (Setup → Device Key Registration → MFA Setup).

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

// Optional: Retrieve client/auth token from app level
final token = await authService.getClientToken();

// Launch Enrollment Flow
await OneAuth().startEnrollmentFlow(
  context,
  user: oneAuthUser,
  token: token,
);
```

---

## Transaction Signing & Canonical Hashing

### 1. Generating Canonical Signature (`X-SIGNATURE`)

Use `TransactionHashService` to build byte-for-byte canonical JSON payloads and generate SHA-256 hashes matching the backend format. Key sorting order is strictly alphabetical: `amount`, `bankTxnId`, `currency`, `customerUniqueKey` *(if present)*, `fromAccount`, `toAccount`.

```dart
final service = TransactionHashService();
final txnRequest = TransactionChallengeRequest(
  amount: '5000.00',
  bankTxnId: bankTxnId,
  customerUniqueKey: 'CUST-987654321',
  currency: 'BDT',
  fromAccount: '1234567890',
  toAccount: '0987654321',
);

// Compute canonical SHA-256 hex string
final xSignature = service.sha256Hex(txnRequest);
```

### 2. Launching Verification UI (`verifyTransaction`)

Pass `txnId`, `txnHash`, `authType`, `token`, and `transactionRequest` to `verifyTransaction`. The SDK automatically embeds the nested `transactionRequest` map and `X-SIGNATURE` header during signature submission.

```dart
final bool? verified = await OneAuth().verifyTransaction(
  context,
  txnId: txnId,
  txnHash: txnHash,
  authType: authType,
  token: token,
  transactionRequest: {
    'bankTxnId': bankTxnId,
    'customerUniqueKey': 'CUST-987654321',
    'fromAccount': '1234567890',
    'toAccount': '0987654321',
    'amount': '5000.00',
    'currency': 'BDT',
  },
);

if (verified == true) {
  // Transaction signed & verified successfully
}
```

### 3. Outgoing Signature Request Payload Structure

When submitting a signature, `OneAuth` sends the following payload structure to `/transactions/{txnId}/signature` with the computed `'X-SIGNATURE'` header:

```json
{
  "deviceUuid": "550e8400-e29b-41d4-a716-446655440000",
  "certificateSerial": "123456789",
  "txnHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "signatureBase64": "MEQCIG...",
  "deviceIntegrity": { ... },
  "pinCode": "1234",
  "transactionRequest": {
    "bankTxnId": "TXN-2026-0001",
    "customerUniqueKey": "CUST-987654321",
    "fromAccount": "1234567890",
    "toAccount": "0987654321",
    "amount": "5000.00",
    "currency": "BDT"
  }
}
```

---

## Security Features

- **Runtime Threat Detection**: Integrates **freeRASP** to detect root/jailbreak, debuggers, emulators, and dynamic instrumentation hooks (Frida).
- **Environment Obfuscation**: Secure secrets and base URLs are compiled and obfuscated via **Envied**.
- **Exception Handling**: Typed security exceptions (`OneAuthSecurityException`, `OneAuthCryptoException`, `OneAuthNetworkException`) for error handling.
