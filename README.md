# Billing Dart SDK

Dart SDK for **using-party client apps** (e.g. Scomm): embedded billing auth, license JWT sync, offline entitlements, and public plan catalog. Not a full Billing API client — portal/admin routes stay on the server.

A Flutter example app is included for local development and manual testing.

**Architecture & roadmap:** [billing/LICENSE_SYNC_AND_SDK_PLAN.md](../billing/LICENSE_SYNC_AND_SDK_PLAN.md)

---

## What this SDK does

| Concern | SDK surface |
|--------|-------------|
| Login | `BillingAuthClient` — PKCE OAuth + discovery (`oauth-providers`, OIDC config) |
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

// Open auth.buildAuthorizeUrl(..., loginProvider: 'google') in browser; user returns with ?code=...
final tokens = await auth.exchangeAuthorizationCode(
  code: authorizationCode,
  redirectUri: pkce.redirectUri,
  codeVerifier: pkce.codeVerifier,
);
```

Use `tokens.accessToken` (audience `billing`) for sync — not raw Google/Microsoft IdP tokens.

Embedded/native clients should pass `loginProvider: 'google'` or `'microsoft'` on `buildAuthorizeUrl` so the server skips its `/login` chooser and redirects straight to the IdP.

### Discover enabled login options

Before showing a login screen, fetch what the server supports:

```dart
final auth = BillingAuthClient(billingBaseUrl: 'https://billing.example.com');

// Option A: provider list only (google / microsoft / email)
final providers = await auth.fetchOAuthProviders();
if (providers.isGoogleEnabled) { /* show Google button */ }
if (providers.isEmailEnabled) { /* show email form */ }

// Option B: full discovery (providers + OIDC endpoints)
final discovery = await auth.discover();
final authorizeEndpoint = discovery.openId.authorizationEndpoint;
```

Public endpoints (no auth): `GET /api/auth/.well-known/oauth-providers` and `GET /api/auth/.well-known/openid-configuration`.

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

## Better Auth alignment (in progress)

The **billing portal** is the reference OAuth client. This SDK’s `BillingAuthClient` still needs parity:

| Gap | Target (match portal) |
|-----|------------------------|
| Scope | Add `offline_access` |
| Audience | `resource=billing` on authorize + token + refresh |
| Token request | `application/x-www-form-urlencoded` |
| Social login | `POST /sign-in/social` + oauth-resume flow |
| Client ID | Configurable (native apps need their own Better Auth client) |

Planned extraction: reusable **`better_auth_client`** Dart package. See **[LICENSE_SYNC_AND_SDK_PLAN.md](../billing/LICENSE_SYNC_AND_SDK_PLAN.md)** §7.

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
