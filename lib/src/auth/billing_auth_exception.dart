/// Thrown when billing auth or OAuth token exchange fails.
class BillingAuthException implements Exception {
  const BillingAuthException(this.message, {this.statusCode, this.responseBody});

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}
