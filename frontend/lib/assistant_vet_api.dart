import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AssistantVetApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  const AssistantVetApiException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() => message;
}

class AssistantVetApi {
  AssistantVetApi._();

  /// Local Windows backend. When the backend is deployed later, only this
  /// constant needs to change.
  static const String baseUrl = 'http://127.0.0.1:8000';

  static Future<Map<String, dynamic>> health() async {
    return _requestJson(
      method: 'GET',
      path: '/health',
      timeout: const Duration(seconds: 8),
    );
  }

  static Future<Map<String, dynamic>> analyzeCase(
    Map<String, dynamic> payload,
  ) async {
    return _requestJson(
      method: 'POST',
      path: '/analyze-case',
      payload: payload,
      timeout: const Duration(minutes: 10),
    );
  }

  static Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? payload,
    required Duration timeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);

    try {
      final uri = Uri.parse('$baseUrl$path');
      final HttpClientRequest request;

      if (method == 'POST') {
        request = await client.postUrl(uri).timeout(
              const Duration(seconds: 10),
            );
      } else {
        request = await client.getUrl(uri).timeout(
              const Duration(seconds: 10),
            );
      }

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
      }

      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);

      dynamic decoded;
      try {
        decoded = body.trim().isEmpty ? <String, dynamic>{} : jsonDecode(body);
      } catch (_) {
        throw AssistantVetApiException(
          'The backend returned a response that was not valid JSON.',
          statusCode: response.statusCode,
          responseBody: body,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = _extractErrorMessage(decoded);
        throw AssistantVetApiException(
          detail.isNotEmpty
              ? detail
              : 'Backend request failed with HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
          responseBody: body,
        );
      }

      if (decoded is! Map) {
        throw const AssistantVetApiException(
          'The backend returned an unexpected response shape.',
        );
      }

      return Map<String, dynamic>.from(decoded);
    } on SocketException {
      throw const AssistantVetApiException(
        'Assistant Vet backend is not reachable. Make sure the local server is running on 127.0.0.1:8000.',
      );
    } on TimeoutException {
      throw const AssistantVetApiException(
        'The analysis request timed out. The local AI may still be busy; check the backend terminal and try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _extractErrorMessage(dynamic decoded) {
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String) return detail;

      if (detail is List && detail.isNotEmpty) {
        final messages = <String>[];
        for (final item in detail) {
          if (item is Map && item['msg'] != null) {
            messages.add(item['msg'].toString());
          } else if (item != null) {
            messages.add(item.toString());
          }
        }
        return messages.join(' | ');
      }

      if (decoded['message'] != null) {
        return decoded['message'].toString();
      }
    }

    return '';
  }
}
