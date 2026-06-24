/// Parses optional org billing context from user input (email, domain, or URL).
///
/// Returns:
/// - `null` when input is empty (no org context)
/// - a normalized email or domain when valid
/// - `''` when input is present but invalid
String? parsePayingPartyContext(String rawValue) {
  final raw = rawValue.trim();
  if (raw.isEmpty) return null;

  final lower = raw.toLowerCase();
  if (_isValidEmail(lower)) return lower;

  final parsed = Uri.tryParse(raw);
  if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
    final host = parsed.host.toLowerCase();
    return _isValidDomain(host) ? host : '';
  }

  if (_isValidDomain(lower)) return lower;
  return '';
}

bool _isValidEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

bool _isValidDomain(String value) =>
    RegExp(r'^(?!-)(?:[a-zA-Z0-9-]{1,63}\.)+[a-zA-Z]{2,63}$').hasMatch(value);
