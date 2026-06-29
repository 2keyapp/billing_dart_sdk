import 'dart:convert';

/// Decodes JWT payload claims without signature verification (client-side display).
Map<String, dynamic>? decodeJwtPayload(String token) {
  final trimmed = token.trim();
  final parts = trimmed.split('.');
  if (parts.length < 2) return null;
  try {
    final raw = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final pad = raw.length % 4;
    final padded = pad == 2
        ? '$raw=='
        : pad == 3
            ? '$raw='
            : raw;
    final decoded = utf8.decode(base64Url.decode(padded));
    final map = jsonDecode(decoded);
    return map is Map<String, dynamic> ? map : null;
  } catch (_) {
    return null;
  }
}
