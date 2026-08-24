# Design: Rust-core SDK, wrappers, and browser SDK

## Context

Today `billing_dart_sdk` is the production client (Scomm/secMail): Better Auth (internal), license ES256 verify, ETag sync, session persist, plan catalog, portal handoff. The multi-SDK architecture doc made Dart the reference for ports to TS/Kotlin/Swift.

We now target a **Rust core for all native runtimes**, language wrappers via FFI, and a **separate browser TS SDK**. Auth remains Better Auth on the server; native auth transport stays adapter-shaped.

Stakeholders: 2key billing platform, Scomm/secMail, billing-portal, future CLI/M2M tools.

## Goals / Non-Goals

### Goals

- One native implementation of billing client truth: configure, license init/sync, bootstrap, catalog, entitlements read, poll policy, typed errors, usage reporting (when API ships).
- Identical OpenAPI + fixture conformance across Rust wrappers and browser TS.
- Host apps depend only on `2key_<lang>_sdk`.
- Clear ports for storage and OAuth launcher (no brand-specific defaults in core).
- CLI proves headless ports and later mTLS/machine identity.

### Non-Goals

- Single WASM binary as the browser product SDK.
- Better Auth reimplementation inside Rust in Phase 1.
- Shipping `@2key/billing-core`, signing private keys, or pricing engines in public SDKs.
- Forcing M2M through Better Auth user sessions.

## Decisions

### Decision 1: Dual reference model

| Surface | Behavioral reference |
|---------|----------------------|
| Native / CLI / mobile / desktop | **`2key_core` (Rust)** + shared conformance fixtures |
| Browser / SPA | **`@2key/ts-sdk`** + same OpenAPI + fixtures |
| Cross-cutting contract | `openapi/2key-billing.yaml` + `docs/auth-protocol.md` |

Dart is the **first production wrapper** and **integration canary**, not the permanent behavioral reference once Rust parity is proven.

**Alternatives considered:** Keep Dart forever-reference (rejects shared native crypto/sync). Pure WASM for browser (rejects cookie/CORS ergonomics and bundle size).

### Decision 2: Layering

```
Host app
  → 2key_<lang>_sdk (idiomatic facade)
    → platform adapters (Storage, AuthLauncher, Http if needed)
    → 2key_core (Rust)           [native path]
    → OR pure TS client          [browser path]
  → HTTPS → /api/auth/* and /api/v1/*
```

**In `2key_core`:**

- Config (`api_base_url`, license public PEM, portal URL, `storage_prefix`, poll policy)
- `/api/v1` client (license + ETag/304, subscriptions/me, plans, future usage)
- Offline ES256 license verify + entitlement decode
- Session orchestration (restore/clear/sync/poll) over opaque storage blobs
- Stable error codes mapped identically in wrappers

**Out of `2key_core` (ports):**

- Secure storage implementation
- OAuth UI / deep link / Custom Tabs / ASWebAuthenticationSession / CLI device flow
- Better Auth cookie/plugin transport (Phase A: keep in Dart auth client; Phase B: optional Rust HTTP auth where protocol is stable)
- Product UI and host-specific addon plan-name hints

### Decision 3: Binding technology

| Consumer | Binding | Rationale |
|----------|---------|-----------|
| Flutter / Dart (Scomm) | **flutter_rust_bridge (FRB)** | Best Flutter ergonomics; async/stream-friendly; existing community patterns |
| CLI | Direct Rust binary / `2key_cli` crate depending on `2key_core` | No FFI |
| Kotlin + Swift (later) | **UniFFI** from same `2key_core` | One IDL → JVM + Swift; avoid maintaining FRB + hand JNI |
| Node native (optional later) | NAPI or UniFFI-adjacent | Prefer `@2key/node-sdk` pure TS/HTTP for services unless native crypto required |
| Browser | **No FFI** — TypeScript OpenAPI client | Cookies, redirects, Web Crypto |

**Rule:** `2key_core` exposes a stable **Rust API + C ABI / UniFFI interface** first; FRB generates Dart from that surface (or a thin `2key_core_ffi` facade crate) so UniFFI and FRB do not fork business logic.

**Alternatives considered:** UniFFI-only for Dart (weaker Flutter DX). cbindgen + hand Dart (high maintenance). wasm-bindgen for browser primary SDK (rejected for product API).

### Decision 4: Auth strategy (phased)

```
Human  → Better Auth session → billing API JWT (aud=billing) → /api/v1
Machine → mTLS / machine token → /api/v1   (CLI / node; not browser)
```

- **Phase A:** Dart wrapper continues to use internal Better Auth Dart client; feeds API JWT + profile into `2key_core` session APIs.
- **Phase B:** CLI (and optionally others) may call `/api/auth/*` via a small Rust auth adapter where flows are loopback/device-code.
- **Browser:** cookie session + redirect; never mTLS.

Auth engines may differ by platform; **billing JWT + license claims must not.**

### Decision 5: Repository layout (target)

```
2keyapp/2key-billing-sdks/          # PUBLIC monorepo (preferred)
  openapi/2key-billing.yaml
  docs/
    architecture.md                 # evolved from billing_dart_sdk doc
    auth-protocol.md
    sdk-conformance.md
  conformance/fixtures/
  crates/
    2key_core/                      # ★ native reference
    2key_cli/                       # thin CLI
  bindings/
    uniffi/                         # generated / scaffolding
  packages/
    dart/                           # 2key_dart_sdk (FRB wrapper)
    ts/                             # @2key/ts-sdk (browser)
    react/                          # optional hooks
    node/                           # optional service/M2M helpers
  examples/
    flutter_app/
    browser_vite/
    cli_smoke/
```

Until the monorepo exists, proposal artifacts live in `billing_dart_sdk/docs/proposals/add-rust-core-sdk/`.

### Decision 6: Public API shape

- Prefer **instance-oriented** clients (`BillingClient` / `TwoKeyClient`) over static globals.
- Required config: API origin, license **public** PEM, `storage_prefix`, deep-link or redirect scheme — **no silent product-brand defaults**.
- Error taxonomy shared (examples): `offline`, `unauthorized`, `license_expired`, `license_invalid`, `not_modified`, `network`, `config`.

### Decision 7: Security boundaries

- Public SDKs: HTTPS + local verify only.
- Never ship server private keys, CA material, or billing-core.
- Storage keys namespaced by `storage_prefix`.
- Distinguish logged-out vs offline in session APIs.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Dual Dart paths (pure Dart vs Rust) during migration | Feature flag; conformance suite gates merge; Scomm canary |
| FRB + UniFFI surface drift | Single Rust facade crate; generate both from one API module |
| Auth still Dart-only delays CLI | Phase B auth adapter; CLI may use device code / pasted token early |
| Browser/native semantic drift | Shared fixtures + CI; forbid divergent claim names |
| FFI build complexity in Flutter CI | Cache Rust toolchains; document host targets; keep core `no_std`-free but lean deps |
| PSGallery / signing CI flakes (unrelated) | Keep deploy pipelines independent of SDK build |

## Migration Plan

1. Lock OpenAPI + extract Dart license/ETag fixtures into `conformance/`.
2. Implement `2key_core` behind the capability checklist (see tasks).
3. FRB Dart wrapper with dual-path in `billing_dart_sdk` / `2key_dart_sdk`.
4. Point Scomm at wrapper when parity green.
5. Ship `2key_cli` smoke against staging.
6. Implement `@2key/ts-sdk` in parallel on OpenAPI (not blocked on Rust).
7. Add UniFFI Kotlin/Swift when facade is stable.
8. Delete pure-Dart license/session duplicates after soak.

**Rollback:** Keep pure Dart path behind flag until soak complete; revert pubspec pin.

## Open Questions

1. Exact FRB version / whether to vendor generated Dart in-repo vs generate in CI.
2. Whether Phase B Rust auth covers social OAuth or only email/device/loopback.
3. M2M: mTLS-only vs opaque machine tokens for constrained environments (inherits parent architecture open decision).
4. Package rename timing: `billing_dart_sdk` → `2key_dart_sdk` before or after Rust dual-path.
5. Publish crates.io for `2key_core` vs git-only until 1.0.

## Capability checklist (must match across native + browser)

1. Configure — API base URL + license public key  
2. Sign-in — platform launcher / redirect  
3. Session — restore, clear, sign-out; missing server session vs offline  
4. API token — mint/refresh billing JWT from auth session  
5. Persist account session — tokens + profile + license JWT + optional ETag  
6. License init — verify saved JWT offline (ES256)  
7. License sync — `GET /api/v1/license` with Bearer; If-None-Match / 304  
8. Bootstrap — `GET /api/v1/subscriptions/me`  
9. Catalog — public plans  
10. Entitlements read — from license payload  
11. Polling / foreground — optional policy in core  
12. Portal handoff — paying-party URL  
13. Usage reporting — when API ships  
14. M2M — CLI/node first when API ships; browser limited  
