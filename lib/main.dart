import 'package:flutter/material.dart';

import 'package:billing_flutter_sdk/billing_flutter_sdk.dart';

void main() {
  runApp(const BillingExampleApp());
}

/// Example app: init on start, paste screen, sync button; show error notification when SDK returns failure.
class BillingExampleApp extends StatelessWidget {
  const BillingExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billing SDK Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BillingExamplePage(),
    );
  }
}

class BillingExamplePage extends StatefulWidget {
  const BillingExamplePage({super.key});

  @override
  State<BillingExamplePage> createState() => _BillingExamplePageState();
}

class _BillingExamplePageState extends State<BillingExamplePage> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _authTokenController = TextEditingController();
  final TextEditingController _payingPartyIdController =
      TextEditingController();
  final TextEditingController _publicKeyPathController =
      TextEditingController();
  final TextEditingController _billingBaseUrlController = TextEditingController(
    text: _defaultBillingBaseUrl,
  );
  bool _syncing = false;
  String? _savedToken;
  static const _defaultBillingBaseUrl = 'http://localhost:3000';

  /// Public key PEM asset. Must match the key that signed the JWT from your backend.
  /// After changing this file, do a full restart (not hot reload) so the new key is loaded.
  static const _publicKeyAsset = 'keys/billing_public.pem';

  @override
  void initState() {
    super.initState();
    _initSdk();
  }

  Future<void> _initSdk() async {
    final baseUrl = _billingBaseUrlController.text.trim().isEmpty
        ? _defaultBillingBaseUrl
        : _billingBaseUrlController.text.trim();
    debugPrint(
      '[BillingExample] Init: configuring SDK with asset $_publicKeyAsset…',
    );

    try {
      await BillingSdk.configureWithAsset(
        billingApiBaseUrl: baseUrl,
        publicKeyAsset: _publicKeyAsset,
      );

      final fp = BillingSdk.loadedKeyFingerprint;

      debugPrint(
        '[BillingExample] Init: public key loaded from asset. '
        'Key fingerprint: ${fp ?? "?"} — compare with last 24 chars of base64 in keys/billing_public.pem',
      );

      if (fp == null) {
        debugPrint(
          '[BillingExample] Init: no key fingerprint (using default?). If you use asset, fingerprint should be set.',
        );
      }
    } on FormatException catch (e) {
      debugPrint('[BillingExample] Init: asset invalid — ${e.message}');
      BillingSdk.configure(billingApiBaseUrl: baseUrl);
    } catch (e, st) {
      debugPrint('[BillingExample] Init: asset load failed — $e');
      debugPrint(st.toString());
      BillingSdk.configure(billingApiBaseUrl: baseUrl);
    }

    debugPrint(
      '[BillingExample] Init: savedToken=${_savedToken != null ? "${_savedToken!.length} chars" : "null"}',
    );

    BillingSdk.init(_savedToken);
    if (mounted) setState(() {});
    final payload = BillingSdk.getPayload();
    if (payload != null) {
      debugPrint(
        '[BillingExample] Init: payload loaded — payingParty=${payload.payingParty.id}, subscriptions=${payload.subscriptionIds.length}',
      );
    } else {
      debugPrint('[BillingExample] Init: no payload (null or invalid token)');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
    );
  }

  void _onPasteVerify() {
    final pasted = _tokenController.text.trim();
    final path = _publicKeyPathController.text.trim();
    final baseUrl = _billingBaseUrlController.text.trim().isEmpty
        ? _defaultBillingBaseUrl
        : _billingBaseUrlController.text.trim();
    debugPrint(
      '[BillingExample] Paste+Verify: input length=${pasted.length}, publicKeyPath=${path.isEmpty ? "none" : path}',
    );
    if (pasted.isEmpty) {
      _showError('Paste a token first.');
      debugPrint('[BillingExample] Paste+Verify: skipped (empty)');
      return;
    }
    if (path.isNotEmpty) {
      try {
        BillingSdk.configure(billingApiBaseUrl: baseUrl, publicKeyPath: path);
        debugPrint(
          '[BillingExample] Paste+Verify: configured with public key from path',
        );
      } on UnsupportedError catch (e) {
        _showError(e.message ?? e.toString());
        return;
      } on FormatException catch (e) {
        _showError(e.message);
        return;
      }
    }
    final result = BillingSdk.verifyAndDecode(pasted);
    switch (result) {
      case VerifySuccess(:final payload):
        _savedToken = pasted;
        debugPrint(
          '[BillingExample] Paste+Verify: SUCCESS — payingParty=${payload.payingParty.id}, '
          'ssoId=${payload.payingParty.ssoId}, subscriptions=${payload.subscriptionIds}, '
          'expiresAt=${payload.expiresAt.toIso8601String()}',
        );
        _showSuccess(
          'Token verified. Paying party: ${payload.payingParty.id}, subscriptions: ${payload.subscriptionIds.length}',
        );
      case VerifyFailure(:final error):
        final alg = BillingSdk.getJwtAlg(pasted);
        debugPrint(
          '[BillingExample] Paste+Verify: FAILED — reason=${error.reason}, message=${error.message}',
        );
        debugPrint(
          '[BillingExample] Token alg=$alg (SDK expects ES256). '
          'Key fingerprint in use: ${BillingSdk.loadedKeyFingerprint ?? "?"}. '
          'If alg is RS256 the backend must sign with ES256; if fingerprint does not match keys/billing_public.pem, do a full restart.',
        );
        _showError(error.message);
    }
  }

  Future<void> _onSync() async {
    final authToken = _authTokenController.text.trim();
    final payingPartyId = _payingPartyIdController.text.trim();
    final baseUrl = _billingBaseUrlController.text.trim().isEmpty
        ? _defaultBillingBaseUrl
        : _billingBaseUrlController.text.trim();
    debugPrint('[BillingExample] Sync: token length=${authToken.length}');
    if (authToken.isEmpty) {
      _showError('Authorization token is required for sync.');
      return;
    }
    BillingSdk.configure(billingApiBaseUrl: baseUrl);
    setState(() => _syncing = true);
    debugPrint(
      '[BillingExample] Sync: calling GET /api/billing/license with X-Paying-Party-Id=${payingPartyId.isEmpty ? "none" : payingPartyId}…',
    );
    final result = await BillingSdk.syncFromServer(
      authorizationToken: authToken,
      payingPartyId: payingPartyId.isEmpty ? null : payingPartyId,
    );

    setState(() => _syncing = false);
    switch (result) {
      case SyncSuccess():
        final payload = BillingSdk.getPayload();

        debugPrint(
          '[BillingExample] Sync: SUCCESS — payload=${payload != null ? "payingParty=${payload.payingParty.id}, subscriptions=${payload.subscriptionIds.length}" : "null"}',
        );

        _showSuccess('Billing synced.');
      case SyncFailure(:final message):
        debugPrint('[BillingExample] Sync: FAILED — message=$message');
        _showError(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = BillingSdk.getPayload();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing SDK Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (payload != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current billing',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text('Paying party: ${payload.payingParty.id}'),
                      Text(
                        'Subscriptions: ${payload.subscriptionIds.join(", ")}',
                      ),
                      if (payload.email != null)
                        Text('Email: ${payload.email}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Public key file path (optional)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _billingBaseUrlController,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: 'Billing base URL',
                hintText: 'e.g. http://localhost:3000 or .../api/billing',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Path to a .pem file containing the Billing API public key. File must contain -----BEGIN PUBLIC KEY----- and -----END PUBLIC KEY-----. Leave empty to use SDK default (test key only). Not supported on web.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _publicKeyPathController,
              maxLines: 1,
              decoration: const InputDecoration(
                hintText: 'e.g. /path/to/billing_public.pem',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Paste token', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Paste signed JWT from billing portal…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _onPasteVerify,
              child: const Text('Verify and save'),
            ),
            const SizedBox(height: 24),
            Text(
              'Sync from server',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'GET /api/billing/license. Authorization token is required (Bearer or SSO token).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _authTokenController,
              decoration: const InputDecoration(
                labelText: 'Authorization token (required)',
                hintText: 'Bearer token or SSO token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _payingPartyIdController,
              decoration: const InputDecoration(
                labelText: 'X-Paying-Party-Id (optional)',
                hintText: 'e.g. 123',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _syncing ? null : _onSync,
              child: _syncing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sync billing'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _authTokenController.dispose();
    _payingPartyIdController.dispose();
    _publicKeyPathController.dispose();
    _billingBaseUrlController.dispose();
    super.dispose();
  }
}
