import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Generates a PKCE code verifier (43–128 chars, RFC 7636).
String generatePkceVerifier({int byteLength = 32}) {
  final random = Random.secure();
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// S256 code challenge from [verifier].
String pkceChallengeS256(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}
