# OneAuth SDK

Unified authentication and identity SDK for mobile applications, providing a secure infrastructure layer for multi-factor authentication (MFA), hardware-backed transaction signing, and client-level security.

---

## Core Principles

- **Infrastructure vs. Business**: OneAuth manages the cryptographic handshake, device key generation, and client-level authentication, while your application manages business-specific user data and logic.
- **Hardware-Backed Security**: Generates and stores cryptographic keys inside the device's Secure Enclave / TEE for hardware-level transaction signing.
- **Secure Persistence**: Uses `flutter_secure_storage` to ensure all sensitive data (TOTP secrets, certificates, tokens) is encrypted at rest.

---

## Features

- **Ready-to-Use MFA Flows**: High-level orchestration via `startEnrollmentFlow` and `verifyTransaction`.
- **Transaction Hash Service**: Built-in canonical JSON serialization and SHA-256 computation (`TransactionHashService`).
- **Hardware Transaction Signing**: Signs transaction challenge hashes with hardware-backed private keys in the TEE/Secure Enclave.
- **Runtime Threat Detection**: Proactive monitoring for Root/Jailbreak, Emulators, and Hooking (Frida) via **freeRASP**.
- **Branded UI**: Professional Material 3 components for Biometrics, PIN, TOTP, and Push Approval.
- **Built-in Feedback Helper**: `OneAuthSnackBar` for consistent success/error messages that match the SDK's look and feel.

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

Then import the SDK wherever you use it:

```dart
import 'package:one_auth/one_auth.dart';
```

This single import exposes `OneAuth`, `OneAuthUser`, `TransactionHashService`, `TransactionChallengeRequest`, and `OneAuthSnackBar`.

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

## Integration Overview

The SDK does not call the bank's Core Banking System (CBS) itself. The **bank's backend (CBS)** issues the client token and creates the transaction challenge. The **host app** calls those bank APIs and then **passes the returned data to the SDK**. The sample banking app follows exactly this pattern:

1. **Get a client token from the bank backend (CBS)**, required by every SDK flow, and pass it to the SDK.
2. **Enroll the user's device** once with `startEnrollmentFlow` (e.g. from a "One Authenticator" quick link on the home screen).
3. **Verify each sensitive transaction**: the app first asks the bank backend (CBS) to create a challenge, then passes the returned `txnId`, `txnHash` and `authenticationType` to `verifyTransaction` (e.g. on the Fund Transfer screen).

| Responsibility | Owner |
| :--- | :--- |
| Issue client token (`getClientToken`) | Bank backend (CBS) |
| Create transaction challenge (`initChallenge`) | Bank backend (CBS) |
| Call the bank APIs and hand data to the SDK | Host app |
| Enrollment UI, device keys, MFA, hardware signing | OneAuth SDK |

```text
Host App                 Bank Backend (CBS)              OneAuth SDK
────────                 ──────────────────              ───────────
Home Screen
getClientToken() ───────► returns client token
      │
      └─ token, user ─────────────────────────────────► startEnrollmentFlow()
                                                        (Setup → Device Key → MFA)

Transfer Screen
initChallenge() ────────► returns txnId, txnHash,
                          authenticationType
getClientToken() ───────► returns client token
      │
      └─ txnId, txnHash, authType, token,
         transactionRequest ────────────────────────► verifyTransaction()
                                                        ──► true / false / null
```

---

## Getting a Client Token

A client token is **mandatory** for both `startEnrollmentFlow` and `verifyTransaction`. It is issued by the **bank backend (CBS)**, not generated by the SDK. Your app requests it and passes it to the SDK.

```bash
curl --location --globoff '{{baseUrl}}/api/v1/auth/client/token' \
--header 'Content-Type: application/json' \
--data '{
  "fiSignature": "Client_Secret" //Optional
}'
```

In the sample app this call is wrapped in a small service so it can be reused by every screen:

```dart
final token = await AuthService().getClientToken();
```

> Request a fresh token right before each flow rather than caching one for the whole session.

---

## MFA Enrollment Flow (`startEnrollmentFlow`)

Pass the user data and the auth token to launch the complete pre-built enrollment UI sequence (Setup → Device Key Registration → MFA Setup).

### `OneAuthUser` fields

| Field | Description |
| :--- | :--- |
| `id` | Your app's unique user ID |
| `name` | Full name |
| `email` | Email address |
| `phoneNumber` | Mobile number |
| `nid` | National ID number |
| `accountNumber` | Primary bank account number |
| `dob` | Date of birth, `YYYY-MM-DD` |

### Example (from the Home screen)

Map your own user model to `OneAuthUser` — do not hard-code values in production.

```dart
onTap: () async {
if (user == null) return;
final navigator = Navigator.of(context);

// 1. Show a loading dialog while the token is fetched
showDialog(
context: context,
barrierDismissible: false,
builder: (_) => const Center(child: CircularProgressIndicator()),
);

try {
final token = await AuthService().getClientToken();

if (!mounted || !context.mounted) return;
navigator.pop(); // 2. Close the loading dialog

// 3. Map your app's user to OneAuthUser
final oneAuthUser = OneAuthUser(
id: user.id,
name: user.name,
email: user.email,
phoneNumber: user.phoneNumber,
nid: user.nid,
accountNumber: user.accountNumber,
dob: user.dob,
);

// 4. Launch the enrollment flow
await OneAuth().startEnrollmentFlow(
context,
user: oneAuthUser,
token: token,
);
} catch (e) {
if (!mounted || !context.mounted) return;
navigator.pop(); // Close the loading dialog on failure too
OneAuthSnackBar.show(
context,
message: 'OneAuth Error: $e',
isError: true,
);
}
},
```

**Notes**
- Capture `Navigator.of(context)` *before* the first `await` so the loading dialog can be closed safely afterwards.
- Always check `mounted` / `context.mounted` after every `await` before touching `context`.
- Close the loading dialog in both the success and the error path.

---

## Transaction Verification Flow

Verifying a transaction is a two-stage process: the **bank backend (CBS)** creates the challenge, then the **SDK** signs it on the device. Your app is the bridge: it calls the bank API and passes the response data to the SDK.

### Step 1 – Initialize the challenge (bank backend / CBS)

Generate a unique `bankTxnId` and call the bank's challenge API (`initChallenge` in the sample app) to create a challenge for the transaction.

**Request**

```bash
curl -X POST "https://your-api-base-url.com/transactions/initiate/challenge" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "X-SIGNATURE: 1e5927c8d9f1db5a90e3eb4c718e244b64f91e976db576e27a92fa80874e4cf1" \
  -d '{
    "bankTxnId": "TXN-1711223344",
    "customerUniqueKey": "CUST-987654321",
    "fromAccount": "1234567890",
    "toAccount": "0987654321",
    "amount": "5000.00",
    "currency": "BDT"
  }'
```

| Header | Description |
| :--- | :--- |
| `X-API-Key` | API key issued to your institution |
| `X-SIGNATURE` | Lowercase hex SHA-256 of the canonical transaction payload. See [Signature Generation](#signature-generation-x-signature) |

The `X-SIGNATURE` must be computed from the **same field values** sent in the request body (`amount`, `bankTxnId`, `currency`, `customerUniqueKey`, `fromAccount`, `toAccount`).

**Response**

The CBS response contains the values the SDK needs:

| Response field | Passed to SDK as |
| :--- | :--- |
| `txnId` | `txnId` |
| `txnHash` | `txnHash` |
| `authenticationType` | `authType` |

```dart
final bankTxnId = 'TXN-${DateTime.now().millisecondsSinceEpoch}';

final challengeResult = await apiService.initChallenge(
  bankTxnId: bankTxnId,
  customerUniqueKey: authUserId ?? 'UNKNOWN',
  fromAccount: fromAccount.accountNumber,
  toAccount: recipientAccount,
  amount: amount,
  currency: 'BDT',
);

final txnId = challengeResult['txnId'];
final txnHash = challengeResult['txnHash'];
final authType = challengeResult['authenticationType'];
```

Only continue if both `txnId` and `txnHash` are present.

### Step 2 – Launch the verification UI (`verifyTransaction`)

Pass the CBS-provided `txnId`, `txnHash` and `authType` (mapped from `authenticationType`), the client `token`, and the `transactionRequest` map to the SDK. The values in `transactionRequest` **must be identical** to those sent to `initChallenge`, because the SDK recomputes the canonical hash from them.

```dart
final token = await AuthService().getClientToken();

if (!mounted || !context.mounted) return;

final bool? verified = await OneAuth().verifyTransaction(
  context,
  txnId: txnId,
  txnHash: txnHash,
  authType: authType,
  token: token,
  transactionRequest: {
    'bankTxnId': bankTxnId,
    'customerUniqueKey': authUserId ?? 'UNKNOWN',
    'fromAccount': fromAccount.accountNumber,
    'toAccount': recipientAccount,
    'amount': amount,
    'currency': 'BDT',
  },
);
```

The SDK automatically embeds the nested `transactionRequest` map and the `X-SIGNATURE` header during signature submission.

### Step 3 – Handle the result

`verifyTransaction` returns `bool?`:

| Result | Meaning | Recommended handling |
| :--- | :--- | :--- |
| `true` | Transaction signed and verified | Show success and continue |
| `false` | Verification failed | Show an error, stop the transfer |
| `null` | User cancelled / dismissed the UI | Treat the same as failure |

```dart
if (verified != true) {
  if (mounted) {
    OneAuthSnackBar.show(
      context,
      message: 'Verification failed or cancelled.',
      isError: true,
    );
  }
  return;
}

if (mounted) {
  OneAuthSnackBar.show(context, message: 'Transfer Successful!');
}
```

### Complete example (Transfer screen)

```dart
Future<void> _handleTransfer() async {
  if (!_formKey.currentState!.validate()) return;
  setState(() => _isLoading = true);

  try {
    final fromAccount = context
        .read<BankProvider>()
        .accounts
        .firstWhere((acc) => acc.id == _selectedFromAccount);
    final apiService = context.read<TransactionApiService>();
    final authUserId = context.read<AuthProvider>().currentUser?.id;

    final bankTxnId = 'TXN-${DateTime.now().millisecondsSinceEpoch}';

    // 1. Create the challenge on the bank backend (CBS)
    final challenge = await apiService.initChallenge(
      bankTxnId: bankTxnId,
      customerUniqueKey: authUserId ?? 'UNKNOWN',
      fromAccount: fromAccount.accountNumber,
      toAccount: _accountController.text,
      amount: _amountController.text,
      currency: 'BDT',
    );

    final txnId = challenge['txnId'];
    final txnHash = challenge['txnHash'];
    final authType = challenge['authenticationType'];

    if (txnId != null && txnHash != null) {
      final token = await AuthService().getClientToken();
      if (!mounted || !context.mounted) return;

      // 2. Pass the CBS data to the SDK to sign & verify on the device
      final bool? verified = await OneAuth().verifyTransaction(
        context,
        txnId: txnId,
        txnHash: txnHash,
        authType: authType,
        token: token,
        transactionRequest: {
          'bankTxnId': bankTxnId,
          'customerUniqueKey': authUserId ?? 'UNKNOWN',
          'fromAccount': fromAccount.accountNumber,
          'toAccount': _accountController.text,
          'amount': _amountController.text,
          'currency': 'BDT',
        },
      );

      // 3. React to the result
      if (verified != true) {
        if (mounted) {
          OneAuthSnackBar.show(context,
              message: 'Verification failed or cancelled.', isError: true);
        }
        return;
      }

      if (mounted) {
        OneAuthSnackBar.show(context, message: 'Transfer Successful!');
      }
    }
  } catch (e) {
    // Strip the "Exception: " prefix for a cleaner user message
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.replaceFirst('Exception: ', '');
    }
    if (mounted) {
      OneAuthSnackBar.show(context, message: message, isError: true);
    }
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
```

---

## Signature Generation (`X-SIGNATURE`)

The `X-SIGNATURE` header on the `initChallenge` request is the SHA-256 hash of a **canonical payload** built from the transaction fields. Use `TransactionHashService` to generate it. During `verifyTransaction`, the SDK rebuilds the same canonical payload from `transactionRequest` and embeds the `X-SIGNATURE` header itself, so you do not compute it again for that step.

### Canonical form

A fixed, ASCII, minified, key-sorted JSON string. Keys are appended in strict alphabetical order:

`amount`, `bankTxnId`, `currency`, `customerUniqueKey` *(only if present and non-empty)*, `fromAccount`, `toAccount`

```json
{"amount":"10000.00","bankTxnId":"TXN12345","currency":"BDT","fromAccount":"123456789","toAccount":"987654321"}
```

Rules (must match the Java backend **byte-for-byte**):

- **Amount** is always formatted as a fixed 2-decimal string using HALF_UP rounding (ties away from zero). `"5000"`, `"5000.0"` and `"5000.00"` all become `"5000.00"`.
- **Optional `customerUniqueKey`** is omitted entirely when null or empty.
- **`txnTimestamp`** is currently excluded from the canonical payload.
- **Escaping**: `\` and `"` in values are escaped with a backslash.
- **Encoding**: ASCII only. Non-ASCII characters are replaced with `?`, matching Java's `getBytes(StandardCharsets.US_ASCII)`.
- **Hash**: lowercase hex SHA-256 of the canonical bytes.

### Dependencies

```yaml
dependencies:
  crypto: ^3.0.0
  decimal: ^3.0.0
```

### Reference implementation

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';

/// Minimal equivalent of TransactionChallengeRequest.
class TransactionChallengeRequest {
  final Decimal amount;
  final String bankTxnId;
  final String? customerUniqueKey;
  final String currency;
  final String fromAccount;
  final String toAccount;
  final DateTime? txnTimestamp; // currently excluded from the canonical payload

  TransactionChallengeRequest({
    required dynamic amount,
    required this.bankTxnId,
    this.customerUniqueKey,
    required this.currency,
    required this.fromAccount,
    required this.toAccount,
    this.txnTimestamp,
  }) : amount = amount is Decimal ? amount : Decimal.parse(amount.toString());
}

/// Canonical form: fixed, ASCII, minified, key-sorted JSON string, e.g.
/// {"amount":"10000.00","bankTxnId":"TXN12345","currency":"BDT","fromAccount":"123456789","toAccount":"987654321"}
///
/// Must produce byte-for-byte the same output as the Java backend.
class TransactionHashService {
  /// Keys are appended in alphabetical order (mechanical, unambiguous rule).
  String canonicalPayload(TransactionChallengeRequest t) {
    final fields = <MapEntry<String, String>>[
      MapEntry('amount', _formatAmount(t)),
      MapEntry('bankTxnId', t.bankTxnId),
      MapEntry('currency', t.currency),
      if (t.customerUniqueKey != null && t.customerUniqueKey!.isNotEmpty)
        MapEntry('customerUniqueKey', t.customerUniqueKey!),
      MapEntry('fromAccount', t.fromAccount),
      MapEntry('toAccount', t.toAccount),
      // MapEntry('txnTimestamp', t.txnTimestamp!.toIso8601String()),
    ];

    final sb = StringBuffer('{');
    sb.writeAll(
      fields.map((e) => '"${e.key}":"${_escape(e.value)}"'),
      ',',
    );
    sb.write('}');
    return sb.toString();
  }

  Uint8List canonicalBytes(TransactionChallengeRequest t) {
    // allowInvalid: true replaces non-ASCII chars with '?', matching
    // Java's getBytes(StandardCharsets.US_ASCII) behavior.
    return Uint8List.fromList(
      const AsciiCodec(allowInvalid: true).encode(canonicalPayload(t)),
    );
  }

  /// Lowercase hex SHA-256 of the canonical bytes.
  String sha256Hex(TransactionChallengeRequest t) {
    return sha256.convert(canonicalBytes(t)).toString();
  }

  /// Fixed 2-decimal string, HALF_UP rounding (ties away from zero).
  static String _formatAmount(TransactionChallengeRequest t) {
    return t.amount.round(scale: 2).toStringAsFixed(2);
  }

  static String _escape(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
```

### Usage: building `X-SIGNATURE` for `initChallenge`

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

// Lowercase hex SHA-256 of the canonical payload -> X-SIGNATURE header
final xSignature = service.sha256Hex(txnRequest);
```

> **Keep the values in sync.** The signature is computed over the canonical values, so the request body, the `X-SIGNATURE` header and the `transactionRequest` passed to `verifyTransaction` must all describe the same transaction. Amounts are normalized to 2 decimals, but every other field must match exactly.

### Outgoing Signature Request Payload

When submitting a signature, `OneAuth` sends the following payload to `/transactions/{txnId}/signature` with the computed `X-SIGNATURE` header:

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

## UI Helper: `OneAuthSnackBar`

A themed snackbar exported by the SDK, used for both enrollment and transaction feedback.

```dart
OneAuthSnackBar.show(
  context,
  message: 'Transfer Successful!',
);

OneAuthSnackBar.show(
  context,
  message: 'Verification failed or cancelled.',
  isError: true,
);
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `context` | `BuildContext` | A mounted context |
| `message` | `String` | Text to display |
| `isError` | `bool` | Optional. Shows error styling when `true` (default `false`) |

---

## Security Features

- **Runtime Threat Detection**: Integrates **freeRASP** to detect root/jailbreak, debuggers, emulators, and dynamic instrumentation hooks (Frida).
- **Environment Obfuscation**: Secure secrets and base URLs are compiled and obfuscated via **Envied**.
- **Exception Handling**: Typed security exceptions (`OneAuthSecurityException`, `OneAuthCryptoException`, `OneAuthNetworkException`) for error handling.

---

## Best Practices

- Use the `txnId`, `txnHash` and `authenticationType` returned by the bank backend (CBS) as-is. The only hash your side computes is the `X-SIGNATURE` for the `initChallenge` request.
- Fetch a fresh client token immediately before each enrollment or verification flow.
- Treat anything other than `verified == true` as a failed transaction.
- Keep the values in `transactionRequest` identical to the ones used when creating the challenge.
- Guard every post-`await` use of `context` with `mounted` / `context.mounted`.
- Always reset loading state in a `finally` block (guarded by `mounted`).
- Never hard-code user data (NID, account number, DOB) outside of local demos.
