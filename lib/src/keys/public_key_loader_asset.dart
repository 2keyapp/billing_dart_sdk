import 'package:flutter/services.dart';

import 'pem_validation.dart';

/// Loads public key PEM from a Flutter asset (e.g. `keys/billing_public.pem`).
///
/// The asset is embedded into the app at build time. Validates that the content
/// contains the standard PEM boundaries (`-----BEGIN PUBLIC KEY-----` and
/// `-----END PUBLIC KEY-----`).
///
/// Add the .pem file to your `pubspec.yaml` under `flutter: assets:`.
///
/// Throws [FormatException] if the asset content is not valid PEM.
/// Throws [FlutterError] / [AssetNotFoundException] if the asset is missing.
Future<String> loadPublicKeyFromAsset(String assetPath) async {
  final path = assetPath.trim();
  if (path.isEmpty) {
    throw FormatException('Asset path must not be empty.');
  }
  final content = await rootBundle.loadString(path);
  validatePublicKeyPem(content);
  return content.trim();
}
