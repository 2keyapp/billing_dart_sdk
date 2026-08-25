# Retirement plan — `billing_dart_sdk`

**Status:** Frozen as of 2026-08-25. Early retirement in favor of **`2key-billing-sdks/packages/dart`**.

## Timeline

| Step | Owner | Done when |
|------|-------|-----------|
| 1. Production sources live in `2key-billing-sdks/packages/dart` | platform | Sources migrated |
| 2. Scomm / secMail `pubspec` → `two_key_dart_sdk` git path | app teams | Apps build + license sync green |
| 3. Archive this GitHub repo (read-only) | platform | No open PRs; README points to monorepo |
| 4. Remove from developer workspaces | everyone | Optional local delete |

## Rules while frozen

- **No new features** in this repo.
- Bugfixes: patch in `2key-billing-sdks/packages/dart` first; cherry-pick here only if a host cannot move yet.
- Binary Private Core / FFI work happens against private **`2key-core-sdk`** binaries, not by restoring Rust into the public tree.

## Compatibility

Hosts may keep `import 'package:two_key_dart_sdk/billing_dart_sdk.dart'` temporarily (re-export in the monorepo package).

## Abandoned branch note (feat/unified-better-auth)

Branch was **3 ahead / 5 behind** `main` at retirement. Unique commits not merged (may already be reflected in monorepo):

- `5ef9d76` feat(auth): add clearLocalAuthSession and export AuthSessionLauncher
- `e6f1d9d` fix(auth): drop removed openid-configuration from SDK discovery
- `c92dbb4` feat(auth): replace PKCE with session-based acquireApiToken

If any behavior is missing from `2key-billing-sdks/packages/dart`, recover from those SHAs before deleting local clones.
