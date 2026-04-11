// ICD360SVPN — lib/src/api/enroll_client.dart
//
// POSTs the 16-char short code to https://vpn.icd360s.de/enroll and
// parses the bundle JSON returned by the agent. Used by
// AppPhaseController.enrollFromCode (M7.2).
//
// Like UpdateService and ChangelogService, this is a PLAIN HTTPS call
// against the OS root store — NOT mTLS — because it must work BEFORE
// the user has enrolled into the WireGuard tunnel. The endpoint sits
// on a public LE certificate; the only secret in the request is the
// 16-char code itself, which the user typed.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/enrollment_bundle.dart';

const String kEnrollUrl = 'https://vpn.icd360s.de/enroll';

class EnrollClientException implements Exception {
  EnrollClientException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'EnrollClientException($statusCode): $message';
}

class EnrollClient {
  EnrollClient({Dio? client, String url = kEnrollUrl})
      : _dio = client ?? Dio(),
        _url = url;

  final Dio _dio;
  final String _url;

  /// Exchange a 16-char short code for an EnrollmentBundle.
  ///
  /// The code may include dashes / spaces / be lowercase — the server
  /// normalizes before lookup, but we trim leading/trailing whitespace
  /// here as a courtesy.
  ///
  /// Throws [EnrollClientException] on any non-200 response or any
  /// transport / parse failure.
  Future<EnrollmentBundle> exchange(String code) async {
    final body = jsonEncode(<String, String>{'code': code.trim()});
    final Response<List<int>> resp;
    try {
      resp = await _dio.post<List<int>>(
        _url,
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.bytes,
          // The server completes well under a second; the long
          // tail is the user's network. Cap at 15s so a stuck
          // POST surfaces as an error instead of hanging the UI.
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Treat any HTTP status as a non-throwing response so we
          // can map 404 / 429 to a friendly Romanian error message
          // instead of a generic DioException stack trace.
          validateStatus: (_) => true,
          headers: <String, String>{
            'Accept': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      throw EnrollClientException(
        'network error: ${e.message ?? e.type.name}',
      );
    }

    final code400 = resp.statusCode ?? 0;
    final bytes = resp.data ?? const <int>[];

    if (code400 == 200) {
      try {
        return EnrollmentBundle.fromBytes(bytes);
      } on EnrollmentBundleException catch (e) {
        throw EnrollClientException('bundle parse failed: ${e.message}');
      }
    }

    // Best-effort error message extraction. The agent's writeError
    // helper produces `{"error": "...", "message": "..."}`.
    String details = '';
    try {
      final Map<String, dynamic> obj = jsonDecode(
        utf8.decode(
          bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          allowMalformed: true,
        ),
      ) as Map<String, dynamic>;
      details = (obj['message'] as String?) ??
          (obj['error'] as String?) ??
          '';
    } catch (_) {
      details = '';
    }

    final friendly = switch (code400) {
      400 => 'Codul are un format greșit. Verifică literele.',
      404 => 'Cod invalid, expirat, sau deja folosit. Cere un cod nou.',
      429 => 'Prea multe încercări. Așteaptă un minut și reîncearcă.',
      503 => 'Serverul nu acceptă enrollment momentan.',
      _ => 'Eroare server (HTTP $code400)',
    };
    throw EnrollClientException(
      details.isNotEmpty ? '$friendly\n$details' : friendly,
      statusCode: code400,
    );
  }
}
