import 'dart:convert';
import 'dart:io';

/// Category of billing sync/bootstrap failure for UI and logging.
enum BillingSyncErrorKind {
  network,
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  serverError,
  invalidResponse,
  configuration,
  technical,
}

/// User-safe billing sync error with optional technical detail for logs.
class BillingSyncError {
  const BillingSyncError({
    required this.kind,
    required this.userMessage,
    this.technicalDetail,
    this.statusCode,
  });

  final BillingSyncErrorKind kind;
  final String userMessage;
  final String? technicalDetail;
  final int? statusCode;

  @override
  String toString() => userMessage;
}

/// Maps HTTP status + body to a [BillingSyncError].
BillingSyncError billingSyncErrorFromHttp({
  required int statusCode,
  required String operation,
  String? responseBody,
}) {
  final serverHint = _extractServerMessage(responseBody);
  final technical = serverHint != null
      ? '$operation HTTP $statusCode: $serverHint'
      : '$operation HTTP $statusCode';

  return switch (statusCode) {
    400 => BillingSyncError(
      kind: BillingSyncErrorKind.badRequest,
      userMessage: serverHint ??
          'Invalid billing request. Check your account and try again.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
    401 => BillingSyncError(
      kind: BillingSyncErrorKind.unauthorized,
      userMessage: 'Session expired or invalid. Sign in again and retry sync.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
    403 => BillingSyncError(
      kind: BillingSyncErrorKind.forbidden,
      userMessage:
          'You do not have access to this billing account. '
          'Try another organization or contact your administrator.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
    404 => BillingSyncError(
      kind: BillingSyncErrorKind.notFound,
      userMessage: 'No billing account or subscriptions found for this user.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
    >= 500 && < 600 => BillingSyncError(
      kind: BillingSyncErrorKind.serverError,
      userMessage:
          'Billing server error. Try again in a few minutes or report this issue.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
    _ => BillingSyncError(
      kind: BillingSyncErrorKind.technical,
      userMessage: 'Technical error. Try again or report this issue.',
      technicalDetail: technical,
      statusCode: statusCode,
    ),
  };
}

/// Maps transport failures (no HTTP response) to a [BillingSyncError].
BillingSyncError billingSyncErrorFromNetwork(
  Object error, {
  required String operation,
}) {
  final type = error.runtimeType.toString();
  final detail = '$operation network error ($type): $error';

  if (_isOfflineError(error)) {
    return BillingSyncError(
      kind: BillingSyncErrorKind.network,
      userMessage:
          'Cannot reach the billing server. Check your internet connection.',
      technicalDetail: detail,
    );
  }

  if (_isTimeoutError(error)) {
    return BillingSyncError(
      kind: BillingSyncErrorKind.network,
      userMessage: 'Billing server timed out. Try again in a moment.',
      technicalDetail: detail,
    );
  }

  return BillingSyncError(
    kind: BillingSyncErrorKind.technical,
    userMessage: 'Technical error. Try again or report this issue.',
    technicalDetail: detail,
  );
}

String? _extractServerMessage(String? responseBody) {
  if (responseBody == null || responseBody.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) {
      for (final key in const ['message', 'error', 'detail', 'title']) {
        final value = decoded[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
        if (first is Map && first['message'] is String) {
          return (first['message'] as String).trim();
        }
      }
    }
  } catch (_) {
    final trimmed = responseBody.trim();
    if (trimmed.length <= 200) return trimmed;
  }
  return null;
}

bool _isOfflineError(Object error) {
  if (error is SocketException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('no address associated');
}

bool _isTimeoutError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('timeout') || text.contains('timed out');
}
