// ICD360SVPN — lib/src/api/api_client.dart
//
// API client for vpn-agent with mTLS. On macOS, uses curl via
// Process.run because dart:io SecurityContext doesn't send client
// certificates on Apple platforms (known bug). On other platforms,
// uses Dio with SecurityContext.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';

import '../models/api_error.dart';
import '../models/health.dart';
import '../models/peer.dart';
import '../models/peer_create_response.dart';
import '../models/traffic_series.dart';
import 'app_logger.dart';
import 'mtls_context.dart';
import 'user_agent.dart';

class ApiClient {
  ApiClient._({
    required this.baseUrl,
    this.certPem = '',
    this.keyPem = '',
    this.caPem = '',
    Dio? dio,
  }) : _dio = dio;

  final String baseUrl;
  final String certPem;
  final String keyPem;
  final String caPem;
  final Dio? _dio;

  /// Files for curl mTLS on macOS.
  String? _certFile;
  String? _keyFile;
  String? _caFile;

  static Future<ApiClient> create({
    required String baseUrl,
    required String certPem,
    required String keyPem,
    required String caPem,
  }) async {
    if (Platform.isMacOS) {
      // On macOS: use curl for API calls (dart:io mTLS is broken).
      // Write PEM files for curl to use.
      final dir = await getApplicationSupportDirectory();
      final certFile = '${dir.path}/_mtls_cert.pem';
      final keyFile = '${dir.path}/_mtls_key.pem';
      final caFile = '${dir.path}/_mtls_ca.pem';
      await File(certFile).writeAsString(certPem);
      await File(keyFile).writeAsString(keyPem);
      await File(caFile).writeAsString(caPem);
      await Process.run('/bin/chmod', <String>['600', keyFile]);
      appLogger.info('API', 'mTLS curl files ready');
      final client = ApiClient._(
        baseUrl: baseUrl,
        certPem: certPem,
        keyPem: keyPem,
        caPem: caPem,
      );
      client._certFile = certFile;
      client._keyFile = keyFile;
      client._caFile = caFile;
      return client;
    }

    // Other platforms: use Dio with SecurityContext.
    final ctx = await buildMtlsContext(
      certPem: certPem,
      keyPem: keyPem,
      caPem: caPem,
    );
    final dio = _buildDio(baseUrl: baseUrl, ctx: ctx);
    return ApiClient._(baseUrl: baseUrl, dio: dio);
  }

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
        validateStatus: (_) => true,
      ),
    );
    final adapter = IOHttpClientAdapter()
      ..createHttpClient = () => HttpClient(context: ctx);
    dio.httpClientAdapter = adapter;
    return dio;
  }

  // ---------------------------------------------------------------
  // Endpoints
  // ---------------------------------------------------------------

  Future<String?> refreshConfig({
    required String publicKey,
    required String privateKey,
  }) async {
    final json = await _request<Map<String, dynamic>>(
      'POST',
      '/v1/config/refresh',
      body: <String, dynamic>{
        'public_key': publicKey,
        'private_key': privateKey,
      },
    );
    return json['wireguard_config'] as String?;
  }

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
  // Request dispatcher
  // ---------------------------------------------------------------

  Future<T> _request<T>(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool expectEmpty = false,
  }) async {
    // macOS: use curl
    if (Platform.isMacOS && _certFile != null) {
      return _curlRequest<T>(method, path, body: body, query: query, expectEmpty: expectEmpty);
    }
    // Other platforms: use Dio
    return _dioRequest<T>(method, path, body: body, query: query, expectEmpty: expectEmpty);
  }

  /// curl-based request for macOS (bypasses dart:io mTLS bug).
  Future<T> _curlRequest<T>(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool expectEmpty = false,
  }) async {
    var url = '$baseUrl$path';
    if (query != null && query.isNotEmpty) {
      final qs = query.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value.toString())}').join('&');
      url = '$url?$qs';
    }

    final args = <String>[
      '-s', '-k',
      '--cert', _certFile!,
      '--key', _keyFile!,
      '--cacert', _caFile!,
      '--connect-timeout', '10',
      '--max-time', '15',
      '-X', method,
      '-H', 'Accept: application/json',
      '-H', 'Content-Type: application/json',
    ];
    if (body != null) {
      args.addAll(<String>['-d', jsonEncode(body)]);
    }
    args.add(url);

    try {
      final result = await Process.run('/usr/bin/curl', args)
          .timeout(const Duration(seconds: 18));
      if (result.exitCode != 0) {
        appLogger.info('API', '$method $path — VPN necesară (curl exit ${result.exitCode})');
        throw ApiError(
          kind: ApiErrorKind.transport,
          message: 'Conectează-te la VPN pentru a accesa datele.',
        );
      }

      final out = (result.stdout as String).trim();
      appLogger.info('API', '$method $path → OK');

      if (expectEmpty || out.isEmpty) return out as T;

      final decoded = jsonDecode(out);

      // Check for error response
      if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
        final status = decoded['status'] as int? ?? 0;
        if (status >= 400) {
          throw ApiError.fromProblemDetails(status, decoded);
        }
      }

      return decoded as T;
    } on ApiError {
      rethrow;
    } catch (e) {
      appLogger.info('API', '$method $path — VPN necesară (agent inaccesibil)');
      throw ApiError(
        kind: ApiErrorKind.transport,
        message: 'Conectează-te la VPN pentru a accesa datele.',
      );
    }
  }

  /// Dio-based request for non-Apple platforms.
  Future<T> _dioRequest<T>(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    bool expectEmpty = false,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio!.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
    } on DioException {
      appLogger.info('API', '$method $path — VPN necesară (agent inaccesibil)');
      throw ApiError(
        kind: ApiErrorKind.transport,
        message: 'Conectează-te la VPN pentru a accesa datele.',
      );
    }

    final status = resp.statusCode ?? 0;
    appLogger.info('API', '$method $path → $status');
    if (status >= 200 && status < 300) {
      if (expectEmpty || resp.data == null) return resp.data as T;
      try {
        return resp.data as T;
      } catch (e) {
        throw ApiError(kind: ApiErrorKind.decoding, message: e.toString());
      }
    }

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
