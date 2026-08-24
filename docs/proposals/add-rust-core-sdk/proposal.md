# Change: Add Rust-core native SDK with language wrappers and browser SDK

**Status:** Proposed (awaiting approval — do not implement until approved)  
**Change ID:** `add-rust-core-sdk`  
**Related:** [2key-billing-sdk-architecture.md](../../2key-billing-sdk-architecture.md)  
**Date:** 2026-08-24  

## Why

Per-language reimplementation of license verify, ETag sync, session orchestration, and entitlements will diverge. Native platforms (Flutter, CLI, Kotlin, Swift, desktop) need one shared implementation; the browser needs a first-class TS SDK because cookies, CORS, and OAuth redirects do not map cleanly onto a Rust FFI/WASM product API.

## What Changes

- Introduce **`2key_core` (Rust)** as the **native behavioral reference** for billing client logic (HTTP `/api/v1`, ES256 license JWT, session orchestration, errors, conformance fixtures).
- Ship **thin wrappers** over `2key_core`: Dart/Flutter (`2key_dart_sdk`), CLI, later Kotlin/Swift/Node — adapters for storage and OAuth chrome only.
- Ship a **separate browser SDK** (`2key_ts_sdk` / `@2key/ts-sdk`) with **protocol parity** (OpenAPI + auth-protocol + fixtures), not binary parity via WASM.
- Evolve the public monorepo layout under `2key-billing-sdks` to host `crates/2key_core`, bindings, and language packages.
- **BREAKING (target):** Dart ceases to be the forever reference; after migration, `2key_core` + conformance fixtures are the source of truth. Dart remains the Scomm/secMail integration canary during transition.
- Host apps still depend on **`2key_<lang>_sdk` only** — never Rust crates, Better Auth, or billing-core directly.

## Impact

- Affected docs: `docs/2key-billing-sdk-architecture.md`, future `auth-protocol.md`, `sdk-conformance.md`, OpenAPI
- Affected code (future): new `2key_core` crate; Dart package becomes FFI facade; new `@2key/ts-sdk`; optional CLI binary
- Affected consumers: Scomm/secMail (Dart wrapper), billing-portal (TS), future CLI/native apps
- Non-impact: Better Auth fork sync model; private billing-server product packages

## Out of scope (this change)

- Implementing usage metering or mTLS CA in any public SDK
- Replacing Better Auth with a Rust auth engine on day one
- Making WASM the only browser delivery mechanism
- Renaming packages in production apps before Phase 1 of the parent architecture plan
