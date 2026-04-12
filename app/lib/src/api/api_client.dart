// ICD360SVPN — lib/src/api/api_client.dart
//
// Dio-based JSON client over mutual TLS for vpn-agent. One method
// per OpenAPI endpoint. RFC 7807 problem+json error responses are
// translated into typed ApiError instances.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/api_error.dart';
import '../models/health.dart';
import '../models/peer.dart';
import '../models/peer_create_response.dart';
import '../models/traffic_series.dart';
import 'app_logger.dart';
import 'mtls_context.dart';
import 'user_agent.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required String certPem,
    required String keyPem,
    required String caPem,
  }) : _dio = _buildDio(
          baseUrl: baseUrl,
          ctx: buildMtlsContext(
            certPem: certPem,
            keyPem: keyPem,
            caPem: caPem,
          ),
        );

  final String baseUrl;
  final Dio _dio;

  static Dio _buildDio({required String baseUrl, required SecurityContext ctx}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        headers: <String, String>{
          'User-Agent': VpnUserAgent.currentOrFallback(),
          'Accept': 'application/json',
        },
        // We do NOT validate the status code in Dio — the request
        // helper does it explicitly so it can decode problem+json
        // bodies for non-2xx responses.
        validateStatus: (_) => true,
      ),
    );

    final adapter = IOHttpClientAdapter()
      ..createHttpClient = () {
        return HttpClient(context: ctx);
      };
    dio.httpClientAdapter = adapter;

    return dio;
  }

  // ---------------------------------------------------------------
  // Endpoints
  // ---------------------------------------------------------------

  Future<Health> health() async {
    final json = await _request<Map<String, dynamic>>('GET', '/v1/health');
    return Health.fromJson(json);
  }

  Future<List<Peer>> listPeers() async {
    final json = await _request<List<dynamic>>('GET', '/v1/peers');
    return json
        .cast<Map<String, dynamic>>()
        .map(Peer.fromJson)
        .toList(growable: false);
  }

  Future<PeerCreateResponse> createPeer({required String name}) async {
    final json = await _request<Map<String, dynamic>>(
      'POST',
      '/v1/peers',
      body: <String, dynamic>{'name': name},
    );
    return PeerCreateResponse.fromJson(json);
  }

  Future<void> setPeerEnabled({
    required String publicKey,
    required bool enabled,
  }) async {
    await _request<dynamic>(
      'PATCH',
      '/v1/peers/${Uri.encodeComponent(publicKey)}',
      body: <String, dynamic>{'enabled': enabled},
      expectEmpty: true,
    );
  }

  Future<void> deletePeer({required String publicKey}) async {
    await _request<dynamic>(
      'DELETE',
      '/v1/peers/${Uri.encodeComponent(publicKey)}',
      expectEmpty: true,
    );
  }

  Future<TrafficSeries> peerBandwidth({
    required String publicKey,
    DateTime? from,
    DateTime? to,
    String granularity = 'hour',
  }) async {
    final qp = <String, dynamic>{'granularity': granularity};
    if (from != null) qp['from'] = from.toUtc().toIso8601String();
    if (to != null) qp['to'] = to.toUtc().toIso8601String();
    final json = await _request<Map<String, dynamic>>(
      'GET',
      '/v1/peers/${Uri.encodeComponent(publicKey)}/bandwidth',
      query: qp,
    );
    return TrafficSeries.fromJson(json);
  }

  // ---------------------------------------------------------------
  // Internal request helper
  // ---------------------------------------------------------------

  Future<T> _request<T>(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool expectEmpty = false,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException catch (dioErr) {
      // The agent listens on https://10.8.0.1:8443 which is reachable
      // ONLY through the WireGuard tunnel. If the user hasn't activated
      // the tunnel yet (or it dropped), every request fails with
      // connection refused / host unreachable / DNS lookup failed.
      // The raw dart:io message ("...this indicates an error which
      // most likely cannot be solved by the library") is meaningless
      // to a non-developer; replace it with a clear Romanian prompt.
      final reason = dioErr.message ?? dioErr.error?.toString() ?? 'unknown';
      appLogger.error('API', '$method $path — transport error: $reason');
      throw ApiError(
        kind: ApiErrorKind.transport,
        message: 'Vă rugăm să vă conectați la VPN pentru a fi afișate '
            'datele. Apăsați butonul "Connect to VPN" din colțul '
            'din dreapta-jos și activați tunelul în WireGuard.',
      );
    }

    final status = resp.statusCode ?? 0;
    appLogger.info('API', '$method $path → $status');
    if (status >= 200 && status < 300) {
      if (expectEmpty || resp.data == null) {
        // Caller asked for void; return whatever T defaults to via
        // a cast — for void/dynamic this is fine.
        return resp.data as T;
      }
      try {
        return resp.data as T;
      } catch (e) {
        throw ApiError(kind: ApiErrorKind.decoding, message: e.toString());
      }
    }

    // Non-2xx — try to decode RFC 7807 first.
    final contentType = resp.headers.value('content-type') ?? '';
    if (contentType.startsWith('application/problem+json') &&
        resp.data is Map<String, dynamic>) {
      throw ApiError.fromProblemDetails(status, resp.data as Map<String, dynamic>);
    }
    appLogger.error('API', '$method $path → HTTP $status');
    throw ApiError(
      kind: ApiErrorKind.http,
      message: 'HTTP $status',
      statusCode: status,
    );
  }
}
