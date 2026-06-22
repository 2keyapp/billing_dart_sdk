import 'package:dio/dio.dart';
import '../exceptions/exceptions.dart';
import 'i_billing_http_client.dart';
import 'token_provider.dart';

/// Dio-based implementation of [IBillingHttpClient].
///
/// Handles auth-token injection via an interceptor, JSON encoding,
/// query-string filtering, and maps HTTP errors to typed exceptions.
class BillingDioClient implements IBillingHttpClient {
  final Dio _dio;
  final String? _payingPartyId;

  BillingDioClient({
    required String baseUrl,
    TokenProvider? tokenProvider,
    String? payingPartyId,
    Map<String, String> defaultHeaders = const {},
    Dio? dio,
  })  : _payingPartyId = payingPartyId?.trim(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _normalizeBillingApiBaseUrl(baseUrl),
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  ...defaultHeaders,
                },
                // Let _parseResponse handle all status codes uniformly.
                validateStatus: (_) => true,
              ),
            ) {
    if (tokenProvider != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.extra['requiresAuth'] == true) {
              final token = await tokenProvider();
              if (token != null) {
                final trimmed = token.trim();
                if (trimmed.isNotEmpty) {
                  options.headers['Authorization'] =
                      trimmed.toLowerCase().startsWith('bearer ')
                          ? trimmed
                          : 'Bearer $trimmed';
                }
              }
              final party = _payingPartyId;
              if (party != null && party.isNotEmpty) {
                options.headers['X-Paying-Party-Id'] = party;
              }
            }
            handler.next(options);
          },
        ),
      );
    }
  }

  static String _normalizeBillingApiBaseUrl(String input) {
    var s = input.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }

    const v1 = '/api/v1';
    const legacy = '/api/billing';
    final lower = s.toLowerCase();
    if (lower.endsWith(legacy)) {
      s = s.substring(0, s.length - legacy.length);
      while (s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
    } else if (lower.endsWith(v1)) {
      return '$s/';
    }

    return '$s$v1/';
  }

  // ─── IBillingHttpClient ───────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String?>? query,
    bool requiresAuth = true,
  }) =>
      _request('GET', path, query: query, requiresAuth: requiresAuth);

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String?>? query,
    bool requiresAuth = true,
  }) =>
      _request('POST', path,
          body: body, query: query, requiresAuth: requiresAuth);

  @override
  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Map<String, String?>? query,
    bool requiresAuth = true,
  }) =>
      _request('PATCH', path,
          body: body, query: query, requiresAuth: requiresAuth);

  @override
  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String?>? query,
    bool requiresAuth = true,
  }) =>
      _request('DELETE', path, query: query, requiresAuth: requiresAuth);

  @override
  void dispose() => _dio.close();

  // ─── Private ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String?>? query,
    bool requiresAuth = true,
  }) async {
    try {
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;

      final filteredQuery = query != null
          ? <String, String>{
              for (final e in query.entries)
                if (e.value != null) e.key: e.value!,
            }
          : null;

      final response = await _dio.request<dynamic>(
        cleanPath,
        data: body,
        queryParameters: filteredQuery,
        options: Options(
          method: method,
          extra: {'requiresAuth': requiresAuth},
        ),
      );

      return _parseResponse(response);
    } on BillingApiException {
      rethrow;
    } on DioException catch (e) {
      throw BillingNetworkException(
        'Network request failed: ${e.message}',
        cause: e,
      );
    } catch (e) {
      throw BillingNetworkException('Unexpected error: $e', cause: e);
    }
  }

  Map<String, dynamic> _parseResponse(Response<dynamic> response) {
    final statusCode = response.statusCode ?? 0;
    final data = response.data;

    Map<String, dynamic>? json;
    if (data is Map<String, dynamic>) {
      json = data;
    } else if (data is String && data.isNotEmpty) {
      json = {'raw': data};
    }

    if (statusCode >= 200 && statusCode < 300) {
      return json ?? {};
    }

    final message = json?['message'] as String? ??
        json?['error'] as String? ??
        'Request failed with status $statusCode';

    throw BillingApiException(
      statusCode: statusCode,
      message: message,
      body: json,
    );
  }
}
