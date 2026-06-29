# Billing Flutter SDK – Development Plan

This document is the single source of truth for the **Billing Flutter SDK**. The SDK is consumed by client-only apps (e.g. Scomm Flutter app); the only server is the Billing API.

---

## 0. Build-time constants and “license” flow

**Build-time constants** (SDK / app):

| Constant | Value |
|----------|--------|
| **BillingURL** | `billing.scomm.ai` (e.g. `https://billing.scomm.ai`) |
| **PublicKeyID** | `t764` |
| **PublicKeyValue** | RSA public key PEM (see Billing API doc `docs/BILLING_TOKEN_PAYLOAD.md` §0) |

**App “license” flow (metaphor):**

- **GET /license (on startup):** App calls Billing API to get the license (signed JWT), then SDK parses it and keeps payload in memory. Requires Billing API to expose **GET /api/billing/license** (or **sdk-token**) with query `email` or `ssoId` – **not yet implemented** (only GET /api/billing/me exists today).
- **POST /license:** User pastes license; SDK verifies and decodes (no server call). Implemented as SDK `verifyAndDecode(pastedString)`.
- **SYNC /license:** Same as GET – call Billing URL to get fresh license; SDK verifies and updates in-memory. Same endpoint as GET /license.

---

## 1. SDK Responsibilities

The SDK is responsible for the following:

---

### 1.1 Init – Decode on app start and keep data in memory

- **On app start**, the SDK provides an **init** method that:
  - Takes the **saved signed JSON** (e.g. from secure storage, previously pasted and persisted by the app).
  - **Decodes and verifies** it (signature + expiry) using the embedded public key.
  - On success: **stores the decoded data in memory** so the rest of the app can use it for **add-on checks** (e.g. “does this user have addon X?”).
- The app is responsible for **persisting** the raw token (e.g. after paste + verify in §1.3) and **passing** it into init on next launch. The SDK does not persist; it only decodes and holds in memory for the session.
- **API (target):** e.g. `BillingSdk.init(String? savedSignedJson)` or `BillingSdk.initFromStorage(Future<String?> Function() readToken)`. After init, the dev accesses billing data via e.g. `BillingSdk.getPayload()` or `BillingSdk.currentPayload` for add-on checks. If `savedSignedJson` is null or invalid, init leaves state empty; the app can show “paste your billing token” or similar.

---

### 1.2 Sync online – API for syncing from the billing server (by user id)

- There will be a **button in the UI** (e.g. “Sync billing”) that triggers a **sync from the billing server**.
- The SDK must **expose an API** for this use case: **sync online** against the Billing API using a **unique identifier** for the user/mailbox (e.g. **user OID**, **SSO id**, or **email** – whatever the Billing API accepts).
- Flow: app calls something like `BillingSdk.syncFromServer(uniqueId: String)` (or `BillingSdk.syncFromServer(userOid: String, ...)`). The SDK:
  - Calls the Billing API (e.g. `GET /api/billing/me?ssoId=...` or similar endpoint that returns the signed JSON or billing payload for that user).
  - On success: **verifies and decodes** the response, **updates in-memory state**, and optionally notifies the app so it can **persist** the new token if the API returns one.
  - On failure: SDK exposes the error so the app can show an **error notification** with the failure cause.
- The SDK needs a **base URL** (or client) for the Billing API, configurable at init or first use.

---

### 1.3 Paste + verify – Serve and verify pasted JSON; expose data to save; errors as notifications

- The SDK is responsible for **accepting the pasted JSON** (signed token), **verifying** it, and **exposing the decoded data** to the app so the app can **save** it (e.g. to secure storage for use in §1.1 on next launch).
- **Success:** Decode succeeds → SDK returns the payload (or updates in-memory state and returns success); the app **saves** the raw token and/or payload for init and add-on checks.
- **Failure:** If verification fails (invalid signature, expired, malformed) → SDK **does not** show UI itself; it **exposes the failure reason** so the **app** can show an **error notification** with the **failure cause** (e.g. “Token expired”, “Invalid signature”, “Malformed token”). The SDK provides a clear error type/message; the app is responsible for displaying it (e.g. snackbar, dialog, banner).

**API (target):** e.g. `BillingSdk.verifyAndSavePastedToken(String pastedJson)` → `Result<BillingTokenPayload, BillingTokenError>` where `BillingTokenError` has a `message` or `cause` for the notification. Or: `verifyAndDecode(String)` returns payload or throws `BillingTokenException` with a user-facing `message`.

---

## 2. Summary Table

| # | Responsibility        | Description |
|---|------------------------|-------------|
| 1 | **Init**              | On app start, decode saved signed JSON and keep data in memory for add-on checks. |
| 2 | **Sync online**       | Expose API for “sync from billing server” by user OID / SSO id / unique id; used when the user taps a sync button in the UI. |
| 3 | **Paste + verify**    | Verify pasted JSON; on success expose data so the app can save it; on failure expose error cause so the app can show an error notification. |

---

## 3. Out of Scope (Handled Elsewhere)

- **UI** for the sync button or paste screen – implemented by the host app; SDK only exposes APIs and error messages.
- **Persistence** of the token – app saves/loads the raw string; SDK uses it in init and after paste.
- **OAuth2 “Add Mailbox”** – handled by the host app or Billing API; see Billing API docs.

---

## 4. API Surface (Target)

```dart
// 1) Init – on app start (saved token from storage)
BillingSdk.init(String? savedSignedJson);
// After init, use for add-on checks:
BillingSdk.getPayload() → BillingTokenPayload?   // or currentPayload

// 2) Sync online – called when user taps “Sync” in UI
BillingSdk.syncFromServer({required String uniqueId});
// uniqueId = user OID, SSO id, or email (as required by Billing API)
// Returns success or failure; on failure, expose cause for error notification.

// 3) Paste + verify – when user pastes JSON
BillingSdk.verifyAndDecode(String pastedJson) → Result<BillingTokenPayload, BillingTokenError>;
// Success: app saves token and/or payload.
// Failure: BillingTokenError has .message / .cause for app to show error notification.

// Config (base URL for sync, optional public key override)
BillingSdk.configure({String? billingApiBaseUrl, String? publicKeyPem});
```

- **Model:** `BillingTokenPayload` with `payingPartyId`, `subscriptionIds`, `email`, `expiresAt`, etc.
- **Errors:** `BillingTokenError` or `BillingTokenException` with a clear, user-facing `message` / `cause` for notifications.

---

## 5. Technical Choices

| Decision | Recommendation |
|----------|----------------|
| **Token format** | JWT (RS256 or ES256). Billing API signs with private key; SDK verifies with public key. |
| **Public key** | Embed in SDK or fetch from Billing API (e.g. `GET /api/billing/public-key`); configurable if needed. |
| **Sync endpoint** | Billing API must expose an endpoint that accepts a unique id (user OID / SSO id / email) and returns the signed token or billing payload for that user. SDK calls it in `syncFromServer`. |
| **In-memory state** | After init or after sync/verify, SDK holds current `BillingTokenPayload` (or null) for `getPayload()` and add-on checks. |

---

## 6. Suggested Package Layout

```
billing_dart_sdk/
├── lib/
│   ├── billing_dart_sdk.dart       # Export file (public API)
│   ├── src/
│   │   ├── billing_sdk.dart           # BillingSdk: init, syncFromServer, verifyAndDecode, configure, getPayload
│   │   ├── models/
│   │   │   ├── billing_token_payload.dart
│   │   │   └── billing_token_error.dart
│   │   ├── verification/
│   │   │   └── token_verifier.dart
│   │   ├── keys/
│   │   │   └── default_public_key.dart
│   │   └── api/
│   │       └── billing_api_client.dart  # For syncFromServer (HTTP client)
│   └── main.dart                      # Example app (init, paste, sync button)
├── test/
├── PLAN.md
├── README.md
└── pubspec.yaml
```

---

## 7. Implementation Steps (Order)

1. Add dependencies: JWT library, HTTP client (for sync).
2. Define `BillingTokenPayload` and `BillingTokenError` (with user-facing message/cause).
3. Implement token verifier (verify + decode; return payload or throw/return error with cause).
4. Implement **init**: accept saved signed JSON, verify, store payload in memory; expose `getPayload()`.
5. Implement **verifyAndDecode** (paste flow): verify pasted string, return payload or error with cause for notification.
6. Implement **syncFromServer**: configurable base URL, call Billing API with unique id, verify response, update in-memory state; on failure expose cause.
7. Configure public key (embed or URL) and optional base URL for sync.
8. Export public API; document that app shows error notifications from SDK error messages.
9. Unit tests: init (valid/invalid/null), verifyAndDecode (success, expired, invalid signature, malformed), sync (success, failure).
10. Example app: init on start, paste screen, sync button; show error notification when SDK returns failure.

---

## 8. API Contracts

Contracts between the **Billing API** (server) and the **SDK** (client), and the **SDK** and the **host app**. All request/response shapes and JWT claims are defined here so both sides can implement against the same contract.

---

### 8.1 Billing API → SDK (endpoints the SDK calls)

#### 8.1.1 Sync – get signed token for user (sync online)

Used by `BillingSdk.syncFromServer(uniqueId)` to fetch a fresh signed token for the user.

| Item | Value |
|------|--------|
| **Method** | `GET` |
| **Path** | `/api/billing/sdk-token` (or `/api/billing/entitlements-token`) |
| **Query (one of)** | `email` (string) **or** `ssoId` (string). Exactly one required. |
| **Request headers** | None required (endpoint is unauthenticated or uses app-level key; TBD by Billing API). |

**Success response** – `200 OK`

| Field | Type | Description |
|-------|------|-------------|
| `signedToken` | `string` | JWT (RS256) signed by Billing API. SDK verifies and decodes; payload shape see §8.3. |

**Example**

```json
{
  "signedToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Error responses**

| Status | Body | SDK behavior |
|--------|------|--------------|
| `400` | `{ "error": "Missing email or ssoId" }` | Expose cause: "Missing user identifier". |
| `404` | `{ "error": "Customer not found" }` | Expose cause: "No billing account found for this user". |
| `500` | `{ "error": "..." }` | Expose cause: "Sync failed. Try again later." |

---

#### 8.1.2 Public key – get verification key (optional; if SDK fetches key at runtime)

Used to verify the JWT signature. SDK may instead embed the public key; then this endpoint is optional.

| Item | Value |
|------|--------|
| **Method** | `GET` |
| **Path** | `/api/billing/public-key` or `/.well-known/jwks.json` |
| **Query** | None. |

**Success response** – `200 OK`

**Option A – PEM**

- `Content-Type: application/x-pem-file` or `text/plain`
- Body: PEM string (e.g. `-----BEGIN PUBLIC KEY----- ... -----END PUBLIC KEY-----`).

**Option B – JWKS**

- `Content-Type: application/json`
- Body: JWKS object, e.g. `{ "keys": [ { "kty": "RSA", "kid": "...", "use": "sig", "n": "...", "e": "..." } ] }`.

---

### 8.2 Signed JWT payload (claims) – Billing API issues, SDK consumes

The Billing API signs a JWT (e.g. RS256); the SDK verifies and decodes it. The **canonical payload structure** (DB-aligned, extendable) is defined in the Billing API repo: **`docs/BILLING_TOKEN_PAYLOAD.md`**. Summary below; SDK must implement parsing for this shape.

**Standard claims:** `exp`, `iat`, `iss`, `aud` (see §8.1 in payload doc).

**Versioning:** `payload_version` (number, e.g. `1`) – SDK should support at least v1 and ignore unknown keys for forward compatibility.

**Paying party (required):** `paying_party_id`, `sso_id`, `billing_email`, `organization_name` (optional: `grace_period_days`, `monthly_billing_anchor`, `annual_billing_anchor`).

**Mailboxes (required):** array `mailboxes[]` – one entry per mailbox the current user has access to. Each object has:

- `mailbox_id` (string, e.g. email like `tamur@gmail.com`)
- `entitlements` (array) – each element: `subscription_id`, `plan_id`, `product_id`, `plan_name`, `product_name`, `subscription_status`, `valid_until` (Unix seconds), `pricing_id`, `billing_interval`, etc.

When the token is issued for a user (by `ssoId` or `email`), **all mailboxes in the array belong to that user**; no client-side filtering by user is needed.

**Optional “per user”:** `user_party_id`, `sso_id_global` at top level when token was issued for a specific user (e.g. sync by user).

**Extension:** optional `metadata` or `features`; SDK can ignore if not needed.

**SDK model** – `BillingTokenPayload` (Dart) must map from these claims, e.g.:

- `payingPartyId` ← `paying_party_id`
- `ssoId` ← `sso_id`
- `billingEmail` / `email` ← `billing_email`
- `organizationName` ← `organization_name`
- `mailboxes` ← `mailboxes[]` → `List<BillingMailbox>` with `mailboxId`, `entitlements` → `List<BillingEntitlement>` (subscriptionId, planId, productId, planName, productName, status, validUntil, etc.)
- `expiresAt` ← `exp` (Unix → `DateTime`)
- `issuedAt` ← `iat` (optional)
- `payloadVersion` ← `payload_version`
- `userPartyId` / `ssoIdGlobal` (optional) when present

For **add-on checks** the app uses `payload.mailboxes` and, for a given mailbox (e.g. current account), checks `mailbox.entitlements.any((e) => e.planId == targetPlanId)` or `e.productId == targetProductId`, and `e.validUntil` for expiry.

---

### 8.3 SDK → Host app (APIs and payloads the SDK exposes)

#### 8.3.1 Init

| API | Input | Output / side effect |
|-----|--------|----------------------|
| `BillingSdk.init(String? savedSignedJson)` | `savedSignedJson`: raw JWT from app storage, or `null`. | Decodes and verifies; on success stores payload in memory. On null/invalid/expired, in-memory state remains empty. No return value (or `void`). |

After init, the app uses `BillingSdk.getPayload()` for add-on checks.

---

#### 8.3.2 Get current payload (add-on checks)

| API | Input | Output |
|-----|--------|--------|
| `BillingSdk.getPayload()` | None. | `BillingTokenPayload?` – current in-memory payload, or `null` if not initialized or invalid. |

**`BillingTokenPayload`** (Dart) – see §8.2 for claim mapping. At minimum:

- `String get payingPartyId`
- `List<String> get subscriptionIds`
- `String? get email`
- `DateTime get expiresAt`

---

#### 8.3.3 Sync from server

| API | Input | Output |
|-----|--------|--------|
| `BillingSdk.syncFromServer({required String uniqueId})` or `BillingSdk.syncFromServer({String? email, String? ssoId})` | `uniqueId`: value to send as either `email` or `ssoId` (SDK or app decides which param to use). Alternatively two optional params: exactly one must be set. | `Future<SyncResult>` where `SyncResult` is either success (payload updated in memory, optional `BillingTokenPayload` returned) or failure with a **user-facing message** for the app to show in an error notification. |

**Success** – SDK updates in-memory state; app may persist the new token if the API returns it (see §8.1.1 response: app can persist `signedToken`).

**Failure** – e.g. `SyncResult.failure(message: "No billing account found for this user")` or `SyncResult.failure(message: "Sync failed. Try again later.")`.

---

#### 8.3.4 Paste + verify

| API | Input | Output |
|-----|--------|--------|
| `BillingSdk.verifyAndDecode(String pastedJson)` | `pastedJson`: raw string pasted by user (JWT). | `Result<BillingTokenPayload, BillingTokenError>` or throws `BillingTokenException`. |

**Success** – Return `BillingTokenPayload`; app saves `pastedJson` (and/or payload) to storage for init on next launch.

**Failure** – Return or throw with **user-facing cause** so the app can show an error notification:

| Cause | Example message |
|-------|------------------|
| Invalid signature | "Invalid token. It may have been copied incorrectly." |
| Expired | "This token has expired. Please sync or get a new token from the billing portal." |
| Malformed | "Invalid format. Please paste the full token from the billing portal." |
| Missing claims | "Token is missing required data." |

**`BillingTokenError`** (Dart) – at minimum:

- `String get message` – user-facing text for notification.
- Optional: `BillingTokenErrorReason get reason` (enum: `invalidSignature`, `expired`, `malformed`, `missingClaims`).

---

### 8.4 Config

| API | Input | Description |
|-----|--------|-------------|
| `BillingSdk.configure({String? billingApiBaseUrl, String? publicKeyPem})` | `billingApiBaseUrl`: base URL for sync and optional public-key fetch (e.g. `https://billing.example.com`). `publicKeyPem`: optional PEM override; if not set, SDK uses embedded key or fetches from API. | Call before first `syncFromServer` or when app starts. |

---

## 9. Billing API Contract (To Align With) – Summary

- **Sync endpoint:** Implement `GET /api/billing/sdk-token?email=...` or `?ssoId=...` returning `{ "signedToken": "<JWT>" }` per §8.1.1.
- **Public key (optional):** Expose `GET /api/billing/public-key` (PEM) or `/.well-known/jwks.json` per §8.1.2 if SDK fetches key at runtime.
- **JWT:** Issue JWT (RS256) with claims per §8.2; SDK verifies and maps to `BillingTokenPayload`.

---

## 10. References

- **Token payload structure (DB-aligned, extendable):** Billing API repo `docs/BILLING_TOKEN_PAYLOAD.md` – canonical JSON shape, DB mapping, versioning, extensions.
- **Auth and OAuth flow:** See Billing API repo docs (e.g. `AUTH_OAUTH_AND_BILLING_FLOW.md`).
- **Billing API:** JWT issuance (payload per BILLING_TOKEN_PAYLOAD.md), public key endpoint, and sync endpoint per §8.

---

## 11. Getting Started

1. Open the SDK project in your IDE.
2. Implement §7 in order.
3. Run tests: `flutter test`.
4. Run example app: `flutter run`.
5. Integrate into the host app (e.g. Scomm Flutter): init on start, wire sync button to `syncFromServer`, wire paste screen to `verifyAndDecode` and show error notification on failure.
