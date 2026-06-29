# Billing Dart SDK

Dart SDK for billing token verification, in-memory entitlements, sync from the Billing API, and paste-and-verify flows. For client-only apps (e.g. Scomm); the only backend is the Billing API.

A Flutter example app is included for local development and manual testing.

---

## Features

- **Init** – Decode saved signed JWT on app start and keep payload in memory for add-on checks.
- **Sync** – Sync billing from the server (GET /api/billing/license) with required authorization token.
- **Paste + verify** – Verify pasted token and expose payload (or a user-facing error) so the app can persist and show notifications.

---

## Installation

Add the package to your app’s `pubspec.yaml`:

```yaml
dependencies:
  billing_dart_sdk:
    path: ../billing_dart_sdk   # or your path / git ref
```

Then run:

```bash
dart pub get   # pure Dart apps
# or
flutter pub get   # Flutter apps
```

---

## Setup

1. **Configure** the SDK once (e.g. at app startup), before any other calls.

   **Recommended (Flutter apps):** Embed the Billing API public key as an asset so it is included in the build. Add the `.pem` file to your `pubspec.yaml` under `flutter: assets:`. Use a path that does **not** start with `assets/` (e.g. `keys/billing_public.pem`) so Flutter web does not double-prefix the URL:

```dart
import 'package:billing_dart_sdk/billing_dart_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BillingSdk.configureWithAsset(
    billingApiBaseUrl: 'https://billing.example.com',
    publicKeyAsset: 'keys/billing_public.pem',
  );
  runApp(MyApp());
}
```

   The asset content is validated (must contain `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`). Alternatively use [configure](#configuration) with `publicKeyPem` or `publicKeyPath`.

2. **Init** on app start with the saved token from your storage (e.g. secure storage). If you have no token yet, pass `null`.

```dart
// In your app’s init flow (e.g. after reading from secure storage)
final savedToken = await storage.readBillingToken(); // your code
BillingSdk.init(savedToken);
```

---

## Usage

### Add-on checks

After `init` (or after a successful sync/verify), use the current payload for entitlements:

```dart
final payload = BillingSdk.getPayload();
if (payload != null && payload.hasSubscription('sub_premium')) {
  // Show premium feature
}
```

### Sync from server

Call when the user taps “Sync billing”. Only the authorization token is required (Bearer or SSO token). GET /api/billing/license with no query params.

```dart
final result = await BillingSdk.syncFromServer(
  authorizationToken: userAuthToken, // required
);
switch (result) {
  case SyncSuccess():
    // Optionally persist the new token; payload is already in memory
  case SyncFailure(:final message):
    // Show message in a snackbar or dialog
}
```

### Paste + verify

When the user pastes a token (e.g. from the billing portal):

```dart
final result = BillingSdk.verifyAndDecode(pastedJson);
switch (result) {
  case VerifySuccess(:final payload):
    // Persist pastedJson (and/or payload) for init on next launch
  case VerifyFailure(:final error):
    // Show error.message in an error notification
}
```

---

## Configuration

| Option | Description |
|--------|-------------|
| `billingApiBaseUrl` | Base URL of the Billing API (required for `syncFromServer`). |
| `publicKeyPem` | EC public key PEM (ES256) to verify JWTs. If omitted, the SDK uses an embedded default; **set from your Billing API in production.** |
| `publicKeyPath` | Path to a `.pem` file on disk. The file is read and validated (must contain `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`). Not supported on web; use `publicKeyPem` or asset there. |
| **Asset (Flutter)** | Call `BillingSdk.configureWithAsset(publicKeyAsset: 'keys/billing_public.pem')` (or `loadPublicKeyFromAsset` then `configure`). Use a path that does not start with `assets/` (e.g. `keys/`) so web works. Add the `.pem` to `pubspec.yaml` under `flutter: assets:`. Same PEM validation applies. |

---

## Important

- **Persistence** – The SDK does not persist tokens. Your app must save/load the raw token and pass it to `init` on launch.
- **Errors** – The SDK returns user-facing messages (`BillingTokenError.message`, `SyncFailure.message`). Your app should show them (e.g. snackbar, dialog).

---

## Development

From the SDK project root:

```bash
flutter pub get
flutter test
flutter run   # runs the Flutter example app
```

- **[PLAN.md](PLAN.md)** – Development plan, API contract, and Billing API alignment.
- **[CODE_REVIEW.md](CODE_REVIEW.md)** – Code review flow and reviewer checklist.
