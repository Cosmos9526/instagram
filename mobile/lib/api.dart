import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin client for the Hashtpa backend. Server URL, token and the active brand
/// are stored on the device.
class Api {
  Api._(this._prefs);
  final SharedPreferences _prefs;
  http.Client client = http.Client();

  static Future<Api> load() async => Api._(await SharedPreferences.getInstance());

  /// As a PWA the app is served by the backend itself, so the default server is the page's origin.
  String get baseUrl => _prefs.getString('base_url') ?? (kIsWeb ? Uri.base.origin : '');
  String get token => _prefs.getString('token') ?? '';
  String? get brandId => _prefs.getString('brand_id');
  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  Future<void> saveServer(String url, String token) async {
    await _prefs.setString('base_url', url.trim().replaceAll(RegExp(r'/+$'), ''));
    await _prefs.setString('token', token.trim());
  }

  Future<void> setBrandId(String id) => _prefs.setString('brand_id', id);

  String mediaUrl(String path) => '$baseUrl$path';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 30)));
    } catch (e) {
      throw ApiException('ارتباط با سرور برقرار نشد');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode == 401) throw ApiException('توکن نامعتبر است');
    if (res.statusCode >= 400) throw ApiException('خطای سرور (${res.statusCode})');
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<void> health() async => _send('GET', '/health');

  Future<List<Brand>> brands() async =>
      [for (final b in await _send('GET', '/brands') as List) Brand.fromJson(b)];

  Future<String> saveBrand(Brand b) async {
    final res = b.id == null
        ? await _send('POST', '/brands', body: b.toJson())
        : await _send('PUT', '/brands/${b.id}', body: b.toJson());
    return res['id'] as String;
  }

  Future<List<Post>> posts(String brandId, {String? date}) async => [
        for (final p in await _send('GET', '/brands/$brandId/posts',
            query: date == null ? null : {'date': date}) as List)
          Post.fromJson(p)
      ];

  Future<Post> post(String id) async => Post.fromJson(await _send('GET', '/posts/$id'));

  Future<Post> generate(String brandId, GenerateRequest r) async =>
      Post.fromJson(await _send('POST', '/brands/$brandId/generate', body: r.toJson()));

  Future<Post> editPost(String id, Map<String, dynamic> content) async =>
      Post.fromJson(await _send('PUT', '/posts/$id', body: {'content': content}));

  /// action: approve | reject | regenerate
  Future<Post> review(String id, String action) async =>
      Post.fromJson(await _send('POST', '/posts/$id/$action'));
}
