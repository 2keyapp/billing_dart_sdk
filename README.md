# billing_dart_sdk — FROZEN / RETIRING

> **This repository is frozen.**  
> Canonical package: [`2key-billing-sdks/packages/dart`](https://github.com/2keyapp/2key-billing-sdks/tree/main/packages/dart) (`two_key_dart_sdk`).  
> See [RETIREMENT.md](RETIREMENT.md) and [retire-billing-dart-sdk.md](https://github.com/2keyapp/2key-billing-sdks/blob/main/docs/retire-billing-dart-sdk.md).

Do **not** add features here. Point hosts at:

```yaml
dependencies:
  two_key_dart_sdk:
    git:
      url: https://github.com/2keyapp/2key-billing-sdks.git
      path: packages/dart
      ref: <PINNED_SHA>
```

```dart
import 'package:two_key_dart_sdk/two_key_dart_sdk.dart';
```

---

## Legacy summary

Dart SDK for **using-party client apps** (e.g. Scomm): embedded billing auth, license JWT sync, offline entitlements, and public plan catalog.

Historical docs remain under `docs/` for reference only.
