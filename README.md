# Billing Dart SDK

Dart SDK for **using-party client apps** (e.g. Scomm): embedded billing auth, license JWT sync, offline entitlements, and public plan catalog. Not a full Billing API client — portal/admin routes stay on the server.

A Flutter example app is included for local development and manual testing.

**Architecture & roadmap:** [billing/LICENSE_SYNC_AND_SDK_PLAN.md](../billing/LICENSE_SYNC_AND_SDK_PLAN.md)

---

## What this SDK does

| Concern | SDK surface |
|--------|-------------|
| Login | `BillingAuthClient` — Better Auth Flutter SDK against billing `/api/auth` |
| Session | `BillingSession` — persist auth + license, online sync, **polling**, offline verify |
| License | `BillingSdk.syncFromServer` → `GET /api/v1/license` (supports **ETag** / **304**) |
| Bootstrap | `BillingSdk.ensureBillingContext` → `GET /api/v1/subscriptions/me` |
| Offline | `BillingSdk.init` / `verifyAndDecode` — ES256 license JWT verify |
| Entitlements | `BillingSdk.getPayload()` — subscriptions, add-ons from JWT |
| Catalog | `BillingSdk.fetchPlanCatalog()` — public monthly/annual plans |
| Polling | `startLicensePolling` (6h), `onAppForeground`, `shouldPollLicenseEntitlements` |

**Paying-party portal** is a separate web app (`billing-portal`). The SDK exposes `BillingAccountSession.canOpenBillingPortal` when the authenticated identity owns the org.

---

## Installation

```yaml
dependencies:
  billing_dart_sdk:
    path: ../billing_dart_sdk   # or your path / git ref
```

`billing_dart_sdk` bundles the [Better Auth Dart client](https://github.com/2keyapp/better-auth/tree/main/packages/flutter/dart). The billing server uses `@better-auth/flutter` from [`release-flutter`](https://github.com/2keyapp/better-auth/tree/release-flutter). See the [Flutter integration guide](https://2keyapp-better-auth.netlify.app/docs/integrations/flutter).

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

### 2. Auth (Better Auth)

Billing hosts Better Auth at `/api/auth`. [BillingAuthClient](lib/src/auth/billing_auth_client.dart) wraps the official `better_auth` Flutter SDK against your billing server.

```dart
final auth = BillingAuthClient(
  billingBaseUrl: 'https://billing.example.com',
  deepLinkScheme: 'scomm',
  storage: SecureBillingAuthStorage(storagePrefix: 'billing_scomm'),
  sessionLauncher: ({required authorizationUrl, required callbackUrl}) async {
    // e.g. flutter_web_auth_2 for Google/Microsoft
    ...
  },
);

// 1) Sign in (Better Auth session on billing server)
await auth.signInSocial(provider: 'google');

// 2) Mint billing API JWT for /api/v1/*
final tokens = await auth.acquireApiToken();

// 3) Persist + sync license
await session.persistAuthTokens(accountKey: userId, tokens: tokens);
await session.syncOnlineForAccount(accountKey: userId);

// Re-mint JWT when near expiry:
await auth.refreshApiToken();

// Open billing portal in browser (session handoff):
final handoffUrl = await auth.createPortalHandoffUrl(
  portalBaseUrl: 'https://portal.example.com',
  redirectPath: '/subscriptions',
);
```

Register `scomm://` in `AUTH_FLUTTER_DEEP_LINK_SCHEMES` on the billing server and deep-link intent filters on Android / URL types on iOS (social OAuth callbacks).

### Discover enabled login options

```dart
final discovery = await auth.discover();
if (discovery.providers.isGoogleEnabled) { /* show Google */ }
if (discovery.providers.isMicrosoftEnabled) { /* show Microsoft */ }
```

Server derives enabled providers from env (`GOOGLE_*`, `MICROSOFT_*`, `APPLE_*`).  
Public endpoints: `GET /api/auth/.well-known/oauth-providers` and `GET /api/auth/.well-known/openid-configuration`.

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

### 3b. Background polling + foreground refresh

After login, register polling once. It **only runs when the user has entitlements** (assigned seat or subscriptions in the license). Manual sync always works.

```dart
session.startLicensePolling(accountKey: userId); // default: every 6 hours

// When the app returns to foreground (WidgetsBindingObserver):
await session.onAppForeground(accountKey: userId);

// Manual "Sync billing" — always fetches a fresh license:
await session.syncOnlineForAccount(accountKey: userId);

// Conditional check (ETag / HTTP 304) — used by polling and foreground:
await session.syncIfLicenseChanged(accountKey: userId);
```

`GET /api/v1/license` supports `If-None-Match` with an `ETag` derived from assigned-seat rows. Unchanged licenses return **304** (no KMS re-sign). The SDK stores `licenseEtag` on [BillingAccountSession].

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
  ifNoneMatch: storedEtag, // optional — omit for always-fresh (manual sync)
);
```

---

## Auth architecture

| Layer | Implementation |
|-------|----------------|
| Identity (login, session, social) | `better_auth` Dart SDK via `BillingAuthClient` |
| Billing API JWT (`aud: billing`) | `GET /api/auth/token` with session cookie (`acquireApiToken` / `refreshApiToken`) |
| License sync / entitlements | `BillingSession` + `BillingSdk` (unchanged) |

Server: `better-auth` + `@better-auth/flutter` on the billing app at `/api/auth`.

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

- **Two token types** — OAuth **access token** (API auth, short-lived) vs **license JWT** (offline entitlements, signed by KMS). The SDK verifies the license JWT locally; access tokens are sent as `Authorization: Bearer`.
- **License sync** — Server returns **ETag**; conditional requests avoid re-signing when seats unchanged. JWT `exp` (default 24h) is separate from per-subscription `valid_until` (paid period end).
- **Polling** — Only runs when user has entitlements; manual sync always available.
- **Persistence** — Use `BillingSession` + `BillingSessionStore` for auth tokens, license JWT, etag, and account context. `BillingSdk.init` only loads into memory.
- **Scope** — This SDK does not wrap checkout, invoices, seat management, or other portal APIs.

---

## Development

```bash
flutter pub get
flutter test
flutter run   # Flutter example app
```

- **[PLAN.md](PLAN.md)** — historical SDK design notes (partially superseded)
- **[billing/LICENSE_SYNC_AND_SDK_PLAN.md](../billing/LICENSE_SYNC_AND_SDK_PLAN.md)** — current architecture, polling, Better Auth roadmap
