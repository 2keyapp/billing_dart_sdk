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

`billing_dart_sdk` bundles the [Better Auth Dart client](https://github.com/2keyapp/better-auth/tree/main/packages/flutter/dart) as an **internal** dependency. Host apps must depend on **`billing_dart_sdk` only** — never on `package:better_auth` (see [docs/2key-billing-sdk-architecture.md](docs/2key-billing-sdk-architecture.md)). The billing server uses `@better-auth/flutter` from [`release-flutter`](https://github.com/2keyapp/better-auth/tree/release-flutter). See the [Flutter integration guide](https://2keyapp-better-auth.netlify.app/docs/integrations/flutter).

```bash
flutter pub get   # or dart pub get
```

---

## Setup

### 1. Configure the SDK

```dart
import 'package:billing_dart_sdk/billing_dart_sdk.dart';

const config = BillingSdkConfig(
  apiBaseUrl: 'https://billing.example.com',
  deepLinkScheme: 'myapp',
  storagePrefix: 'billing_myapp',
  publicKeyAsset: 'keys/billing_public.pem',
  portalBaseUrl: 'https://billing.example.com', // optional; defaults to apiBaseUrl
);

await BillingSdk.configureFrom(config);
```

| Option | Description |
|--------|-------------|
| `apiBaseUrl` | Billing host origin (required). |
| `deepLinkScheme` | OAuth callback scheme (required), e.g. `myapp`. |
| `storagePrefix` | Shared namespace for auth + session storage (required). |
| `publicKeyPem` / `publicKeyAsset` | EC PEM for license JWT verification (ES256). |
| `portalBaseUrl` | Portal/shop origin (optional). |
| `shopPath` | Marketplace path (default `/shop`). |
| `addonPlanNameHints` | Host product plan-name map (default empty). |

### 2. Auth

Billing hosts auth at `/api/auth`. [BillingAuthClient](lib/src/auth/billing_auth_client.dart) wraps it. Host apps never import `better_auth` — only `billing_dart_sdk`.

```dart
final auth = BillingAuthClient.fromConfig(
  config,
  sessionLauncher: ({required authorizationUrl, required callbackUrl}) async {
    // Host OAuth browser / loopback / deep-link flow
    ...
  },
);
auth.setOnline(false); // refresh session explicitly instead of background poll

final session = BillingSession(
  store: SecureBillingSessionStore(storagePrefix: config.storagePrefix),
);

// 1) Sign in
await auth.signInSocial(provider: 'google');

// 2) Mint billing API JWT + persist (merges session profile when JWT omits sub/email)
final tokens = await auth.acquireApiToken();
final authSession = await auth.getSession();
await session.persistAfterSignIn(
  accountKey: authSession!.user.id,
  sessionUser: authSession.user,
  tokens: tokens,
  loginProvider: 'google',
);
await session.syncOnlineForAccount(accountKey: authSession.user.id);

// Portal handoff:
final handoffUrl = await auth.createPortalHandoffUrl(
  portalBaseUrl: config.resolvedPortalBaseUrl,
  redirectPath: '/subscriptions',
);
```

Register `{scheme}://` in `AUTH_FLUTTER_DEEP_LINK_SCHEMES` on the billing server and deep-link intent filters on Android / URL types on iOS.

### Discover enabled login options

```dart
final discovery = await auth.discover();
if (discovery.isGoogleEnabled) { /* show Google */ }
if (discovery.isMicrosoftEnabled) { /* show Microsoft */ }
if (discovery.isAppleEnabled) { /* show Apple */ }
```

Server derives enabled providers from env (`GOOGLE_*`, `MICROSOFT_*`, `APPLE_*`).  
Public endpoint: `GET /api/auth/.well-known/oauth-providers`. JWT verification uses `GET /api/auth/jwks`.

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
| `BillingSdkConfig.apiBaseUrl` | Billing host origin (required for API calls). |
| `BillingSdkConfig.deepLinkScheme` | OAuth deep-link scheme (required). |
| `BillingSdkConfig.storagePrefix` | Shared auth + session key prefix (required). |
| `BillingSdkConfig.publicKeyPem` / `publicKeyAsset` | EC PEM for license JWT verification (ES256). |
| `BillingSdkConfig.portalBaseUrl` | Portal origin (optional; defaults to apiBaseUrl). |
| `BillingSdkConfig.shopPath` | Shop path (default `/shop`). |
| `BillingSdkConfig.addonPlanNameHints` | Host product plan-name hints (default empty). |

Use [SecureBillingSessionStore] for persistence (or implement [BillingSessionStore]).

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
