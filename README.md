# Billing Dart SDK

Dart SDK for **using-party client apps** (e.g. Scomm): embedded billing auth, license JWT sync, offline entitlements, and public plan catalog. Not a full Billing API client — portal/admin routes stay on the server.

A Flutter example app is included for local development and manual testing.

---

## What this SDK does

| Concern | SDK surface |
|--------|-------------|
| Login | `BillingAuthClient` — PKCE OAuth against `/api/auth` |
| Session | `BillingSession` — persist auth + license, online sync, offline verify |
| License | `BillingSdk.syncFromServer` → `GET /api/v1/license` |
| Bootstrap | `BillingSdk.ensureBillingContext` → `GET /api/v1/subscriptions/me` |
| Offline | `BillingSdk.init` / `verifyAndDecode` — ES256 license JWT verify |
| Entitlements | `BillingSdk.getPayload()` — subscriptions, add-ons from JWT |
| Catalog | `BillingSdk.fetchPlanCatalog()` — public monthly/annual plans |

**Paying-party portal** access is separate; the server validates portal users. The SDK exposes `BillingAccountSession.canOpenBillingPortal` when the authenticated identity owns the org.

---

## Installation

```yaml
dependencies:
  billing_dart_sdk:
    path: ../billing_dart_sdk   # or your path / git ref
```

```bash
flutter pub get   # or dart pub get
```

---

## Setup

### 1. Configure the SDK

```dart
import 'package:billing_dart_sdk/billing_dart_sdk.dart';

await BillingSdk.configureWithAsset(
  billingApiBaseUrl: 'https://billing.example.com',
  publicKeyAsset: 'keys/billing_public.pem',
);
```

- `billingApiBaseUrl` — billing **origin** (e.g. `https://billing.example.com`). The SDK calls `/api/v1/*` internally.
- `publicKeyPem` / asset — EC public key (ES256) to verify **license** JWTs from `GET /api/v1/license`.

### 2. Auth (PKCE)

Billing hosts its own auth at `/api/auth`. The app opens a browser for login, then exchanges the authorization code:

```dart
final auth = BillingAuthClient(billingBaseUrl: 'https://billing.example.com');
final pkce = BillingPkceRequest.create(
  redirectUri: 'myapp://auth/callback',
);

// Open auth.buildAuthorizeUrl(...) in browser; user returns with ?code=...
final tokens = await auth.exchangeAuthorizationCode(
  code: authorizationCode,
  redirectUri: pkce.redirectUri,
  codeVerifier: pkce.codeVerifier,
);
```

Use `tokens.accessToken` (audience `billing`) for sync — not raw Google/Microsoft IdP tokens.

### 3. Session + sync

Implement `BillingSessionStore` (secure storage) or use `InMemoryBillingSessionStore` for tests:

```dart
final session = BillingSession(store: mySecureStore);

await session.persistAuthTokens(accountKey: userId, tokens: tokens);

final outcome = await session.syncOnlineForAccount(accountKey: userId);
switch (outcome) {
  case SessionSyncSuccess(:final session):
    // session.licensePayload, session.billingStats, session.isUsingParty
  case SessionSyncFailure(:final message):
    // show message
}
```

On next launch:

```dart
await session.initForAccount(userId); // restores license JWT → BillingSdk.getPayload()
```

### 4. Offline / paste

```dart
await session.verifyOfflineToken(accountKey: userId, token: pastedJwt);
// or
BillingSdk.verifyAndDecode(pastedJwt);
```

---

## Usage

### Entitlements (from license JWT)

```dart
final payload = BillingSdk.getPayload();
if (payload != null && payload.hasAddon('ai_assistant')) {
  // enable feature
}
if (payload?.hasPlan('plan_premium') ?? false) { /* ... */ }
```

### Plan catalog (public, no auth)

```dart
final catalog = await BillingSdk.fetchPlanCatalog(productId: 1);
// catalog.monthly, catalog.annual
```

### Manual sync (without session helper)

```dart
final result = await BillingSdk.syncFromServer(
  authorizationToken: tokens.accessToken,
  payingPartyId: null, // optional X-Paying-Party-Id for multi-org
);
```

---

## Configuration

| Option | Description |
|--------|-------------|
| `billingApiBaseUrl` | Billing host origin (required for API calls). |
| `publicKeyPem` | EC PEM for license JWT verification (ES256). |
| `publicKeyPath` | Load PEM from disk (not on web). |
| `publicKeyAsset` | Flutter asset path (recommended; avoid `assets/` prefix on web). |

---

## Important

- **Two token types** — OAuth **access token** (API auth) vs **license JWT** (offline entitlements). The SDK verifies the license JWT locally; access tokens are sent as `Authorization: Bearer`.
- **Persistence** — Use `BillingSession` + `BillingSessionStore` for auth tokens, license JWT, and account context. `BillingSdk.init` only loads into memory.
- **Scope** — This SDK does not wrap checkout, invoices, seat management, or other portal APIs. Call those from the portal or integrate separately if needed.

---

## Development

```bash
flutter pub get
flutter test
flutter run   # Flutter example app
```

- **[PLAN.md](PLAN.md)** — development plan and API alignment notes.
