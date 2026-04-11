// ICD360SVPN — lib/src/models/api_error.dart
//
// Anything that can go wrong while talking to vpn-agent is normalised
// into one of these. The view layer matches on .kind for special
// cases (e.g. .missingIdentity → bounce back to enrollment).

class ApiError implements Exception {
  ApiError({required this.kind, required this.message, this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiError($kind): $message';

  /// Build an [ApiError] from an RFC 7807 application/problem+json
  /// response body.
  factory ApiError.fromProblemDetails(int statusCode, Map<String, dynamic> body) {
    final detail = body['detail'] as String?;
    final title = body['title'] as String?;
    return ApiError(
      kind: ApiErrorKind.problemDetails,
      message: detail?.isNotEmpty == true ? '$title: $detail' : (title ?? 'HTTP $statusCode'),
      statusCode: statusCode,
    );
  }
}

enum ApiErrorKind {
  /// Lower-level transport problem: DNS, TCP, TLS handshake.
  transport,

  /// Server returned a non-2xx response we could not parse as
  /// problem+json.
  http,

  /// RFC 7807 problem+json response.
  problemDetails,

  /// JSON decoding failed on a 2xx body.
  decoding,

  /// No client identity in secure storage — caller must enroll first.
  missingIdentity,
}
