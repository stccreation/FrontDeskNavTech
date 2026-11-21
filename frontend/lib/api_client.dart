import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.status, this.code});

  final String message;
  final int? status;
  final String? code;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? csrfToken;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _request(
        () =>
            _client.get(Uri.base.resolve(path).replace(queryParameters: query)),
      );

  Future<Map<String, dynamic>> post(String path, Map<String, Object?> data) =>
      _request(
        () => _client.post(
          Uri.base.resolve(path),
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': csrfToken ?? '',
          },
          body: jsonEncode(data),
        ),
      );

  Future<Map<String, dynamic>> postWithFiles(
    String path,
    Map<String, Object?> data,
    List<http.MultipartFile> files,
  ) => _request(() async {
    final request = http.MultipartRequest('POST', Uri.base.resolve(path))
      ..headers['X-CSRF-Token'] = csrfToken ?? ''
      ..fields.addAll({
        for (final entry in data.entries) entry.key: '${entry.value}',
      })
      ..files.addAll(files);
    return http.Response.fromStream(await _client.send(request));
  }, timeout: const Duration(minutes: 2));

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await send().timeout(timeout);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          payload['error'] as String? ?? 'The request could not be completed.',
          status: response.statusCode,
          code: payload['code'] as String?,
        );
      }
      return payload;
    } on http.ClientException {
      throw const ApiException('Could not reach Frontdesk. Try again.');
    } on TimeoutException {
      throw const ApiException(
        'Frontdesk took too long to respond. Try again.',
      );
    } on FormatException {
      throw const ApiException('Frontdesk returned an unexpected response.');
    } on TypeError {
      throw const ApiException('Frontdesk returned an unexpected response.');
    }
  }

  void close() => _client.close();
}
