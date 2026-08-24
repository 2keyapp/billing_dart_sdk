# Tasks: add-rust-core-sdk

## 0. Approval gate

- [ ] 0.1 Review `proposal.md` and `design.md`
- [ ] 0.2 Resolve open questions in `design.md` (FRB versioning, auth Phase B scope, rename timing, crates.io)
- [ ] 0.3 Approve this change before any implementation

## 1. Spec lock (protocol)

- [ ] 1.1 Export / update `openapi/2key-billing.yaml` for current `/api/v1` (license, subscriptions/me, plans)
- [ ] 1.2 Write `docs/auth-protocol.md` (browser cookies vs native deep-link/loopback)
- [ ] 1.3 Extract conformance fixtures from Dart tests (ES256 JWTs, ETag 200/304, entitlement claim names)
- [ ] 1.4 Document shared error code list

## 2. Rust core (`2key_core`)

- [ ] 2.1 Scaffold crate (workspace under future `2key-billing-sdks` or interim repo)
- [ ] 2.2 Config types — required `api_base_url`, public PEM, `storage_prefix`; no brand defaults
- [ ] 2.3 Storage + Auth + Clock traits (ports)
- [ ] 2.4 License JWT verify/decode (ES256) matching Dart payload fields
- [ ] 2.5 HTTP client for license sync (ETag / 304), subscriptions/me, plans
- [ ] 2.6 Session orchestration — persist, restore, clear, sync, poll policy
- [ ] 2.7 Typed errors + mapping table for wrappers
- [ ] 2.8 Rust unit tests against conformance fixtures

## 3. Bindings facade

- [ ] 3.1 Define stable Rust facade module intended for FFI (no internal types leaked)
- [ ] 3.2 Choose and pin FRB version; generate Dart bindings for facade
- [ ] 3.3 (Later) UniFFI scaffolding for Kotlin/Swift from same facade
- [ ] 3.4 CI: build `2key_core` + Dart bindings on Linux/macOS/Windows targets as needed

## 4. Dart wrapper (canary)

- [ ] 4.1 Add dual-path in `billing_dart_sdk` / `2key_dart_sdk` (pure Dart vs Rust) behind flag
- [ ] 4.2 Map existing public surface (`BillingSdkConfig`, session, license sync) onto facade
- [ ] 4.3 Keep Better Auth Dart client internal for Phase A token mint
- [ ] 4.4 Host still supplies `AuthSessionLauncher` + storage
- [ ] 4.5 Conformance + integration tests green on Rust path
- [ ] 4.6 Scomm/secMail optional canary pin; soak; then default Rust path
- [ ] 4.7 Remove duplicate pure-Dart license/session code after soak

## 5. CLI

- [ ] 5.1 `2key_cli` binary on `2key_core`
- [ ] 5.2 Headless auth adapter (loopback and/or device/pasted token)
- [ ] 5.3 OS keyring storage adapter
- [ ] 5.4 Smoke: configure → auth → license sync against staging

## 6. Browser SDK (`@2key/ts-sdk`)

- [ ] 6.1 Scaffold package with OpenAPI-generated or hand-maintained `/api/v1` client
- [ ] 6.2 Cookie/redirect auth per `auth-protocol.md`
- [ ] 6.3 License verify via Web Crypto / jose; same claim names as fixtures
- [ ] 6.4 Session helpers + portal handoff
- [ ] 6.5 Conformance suite in CI
- [ ] 6.6 Migrate billing-portal to `@2key/ts-sdk` (when ready)

## 7. Monorepo & naming

- [ ] 7.1 Create / migrate to `2key-billing-sdks` layout per design
- [ ] 7.2 Rename `billing_dart_sdk` → `2key_dart_sdk` (timing per open question)
- [ ] 7.3 Update parent architecture doc status to Adopted for Rust-core sections
- [ ] 7.4 App docs: hosts depend on `2key_<lang>_sdk` only

## 8. Later languages / M2M

- [ ] 8.1 UniFFI Kotlin SDK
- [ ] 8.2 UniFFI Swift SDK
- [ ] 8.3 Usage event APIs in core + wrappers when server ships
- [ ] 8.4 mTLS / machine-token helpers in CLI / node first
