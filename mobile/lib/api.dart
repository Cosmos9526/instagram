import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'demo.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// Client for the Postyar backend. Server address and login token are stored on the device.
class Api {
  Api._(this._prefs);
  final SharedPreferences _prefs;
  http.Client client = http.Client();

  static Future<Api> load() async =>
      Api._(await SharedPreferences.getInstance());

  /// As a PWA the app is served by the backend itself, so the default server is the page's origin.
  String get baseUrl =>
      _prefs.getString('base_url') ?? (kIsWeb ? Uri.base.origin : '');
  String get token => _prefs.getString('token') ?? '';
  bool get hasServer => baseUrl.isNotEmpty || isDemo;
  bool get isLoggedIn => token.isNotEmpty;

  Future<void> saveServer(String url) =>
      _prefs.setString('base_url', url.trim().replaceAll(RegExp(r'/+$'), ''));

  String? get activeBrandId => _prefs.getString('active_brand_id');

  Future<void> selectBrand(String id) async {
    await _prefs.setString('active_brand_id', id);
  }

  Future<void> logout() async {
    await _prefs.remove('token');
    await _prefs.remove('active_brand_id');
  }

  String mediaUrl(String path) => '$baseUrl$path';

  /// Small JPEG of a rendered slide (much lighter than the 1080px PNG); `path` is a /media/... path.
  String thumbUrl(String path, int width) => path.startsWith('/media/')
      ? '$baseUrl/thumb/${path.substring(7)}?w=$width'
      : mediaUrl(path);

  Map<String, String> get _headers => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json; charset=utf-8',
  };

  static const _messages = {
    401: 'Please sign in again',
    403: 'Registration is closed',
    404: 'Not found',
    409: 'This action is currently unavailable',
  };

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException('Could not connect. Please try again.');
    }
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 400) {
      throw ApiException(
        _messages[res.statusCode] ?? 'Server error (${res.statusCode})',
        res.statusCode,
      );
    }
    try {
      return text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      throw ApiException('Unexpected response. Please try again.');
    }
  }

  // ---- account ----

  Future<AppUser> _auth(String path, Map<String, String> body) async {
    final res = await _send('POST', path, body: body);
    await _prefs.setString('token', res['token'] as String);
    return AppUser.fromJson(res['user']);
  }

  Future<AppUser> login(String email, String password) async {
    try {
      return await _auth('/auth/login', {'email': email, 'password': password});
    } on ApiException catch (e) {
      throw e.status == 401
          ? ApiException('Incorrect email or password', 401)
          : e;
    }
  }

  Future<AppUser> register(String name, String email, String password) async {
    try {
      return await _auth('/auth/register', {
        'name': name,
        'email': email,
        'password': password,
      });
    } on ApiException catch (e) {
      if (e.status == 409) {
        throw ApiException(
          'This email is already registered. Please sign in.',
          409,
        );
      }
      if (e.status == 422) {
        throw ApiException(
          'Enter a valid email and a password of at least 8 characters',
          422,
        );
      }
      rethrow;
    }
  }

  Future<AppUser> me() async =>
      AppUser.fromJson(await _send('GET', '/auth/me'));

  Future<AppUser> updateMe({String? name, String? password}) async =>
      AppUser.fromJson(
        await _send(
          'PUT',
          '/auth/me',
          body: {'name': ?name, 'password': ?password},
        ),
      );

  // ---- projects ----

  Future<List<Brand>> brands() async => [
    for (final b in await _send('GET', '/brands') as List) Brand.fromJson(b),
  ];

  Future<String> saveBrand(Brand b) async {
    final res = b.id == null
        ? await _send('POST', '/brands', body: b.toJson())
        : await _send('PUT', '/brands/${b.id}', body: b.toJson());
    return res['id'] as String;
  }

  /// Proposed project (profile, weekly plan, first-week ideas) from a website and/or Instagram page.
  Future<Map<String, dynamic>> analyze(
    String website,
    String instagram,
  ) async =>
      (await _send(
            'POST',
            '/analyze',
            body: {'website': website, 'instagram': instagram},
          ))
          as Map<String, dynamic>;

  Future<void> deleteBrand(String id) async => _send('DELETE', '/brands/$id');

  // ---- catalog ----

  Catalog? _catalog;
  Future<Catalog> catalog() async =>
      _catalog ??= Catalog.fromJson(await _send('GET', '/catalog'));

  // ---- research ----

  Future<List<Research>> research(String brandId) async => [
    for (final r in await _send('GET', '/brands/$brandId/research') as List)
      Research.fromJson(r),
  ];

  Future<Research> startResearch(String brandId, String focus) async =>
      Research.fromJson(
        await _send(
          'POST',
          '/brands/$brandId/research',
          body: {'focus': focus},
        ),
      );

  // ---- posts ----

  Future<List<Post>> posts(String brandId) async => [
    for (final p in await _send('GET', '/brands/$brandId/posts') as List)
      Post.fromJson(p),
  ];

  Future<void> deletePost(String id) async => _send('DELETE', '/posts/$id');

  Future<CompetitorScan> searchPrices(String brandId, String query) async =>
      CompetitorScan.fromJson(
        await _send(
          'POST',
          '/brands/$brandId/competitors/prices',
          body: {'query': query},
        ),
      );

  Future<Post> post(String id) async =>
      Post.fromJson(await _send('GET', '/posts/$id'));

  Future<Post> generate(String brandId, GenerateRequest r) async =>
      Post.fromJson(
        await _send('POST', '/brands/$brandId/generate', body: r.toJson()),
      );

  Future<Post> editPost(String id, Map<String, dynamic> content) async =>
      Post.fromJson(
        await _send('PUT', '/posts/$id', body: {'content': content}),
      );

  /// action: approve | reject | regenerate
  Future<Post> review(String id, String action) async =>
      Post.fromJson(await _send('POST', '/posts/$id/$action'));

  // ---- competitors ----

  Future<List<Competitor>> competitors(String brandId) async => [
    for (final c in await _send('GET', '/brands/$brandId/competitors') as List)
      Competitor.fromJson(c),
  ];

  Future<List<Competitor>> saveCompetitors(
    String brandId,
    List<Competitor> items,
  ) async {
    final res = await _send(
      'PUT',
      '/brands/$brandId/competitors',
      body: {
        'competitors': [for (final c in items) c.toJson()],
      },
    );
    return [for (final c in res as List) Competitor.fromJson(c)];
  }

  Future<List<Competitor>> parseCompetitorsText(
    String brandId,
    String text,
  ) async {
    final res = await _send(
      'POST',
      '/brands/$brandId/competitors/parse',
      body: {'text': text},
    );
    return [for (final c in res as List) Competitor.fromJson(c)];
  }

  Future<CompetitorScan> startCompetitorScan(
    String brandId, {
    List<String> only = const [],
  }) async => CompetitorScan.fromJson(
    await _send(
      'POST',
      '/brands/$brandId/competitors/scan',
      body: {'only': only},
    ),
  );

  Future<List<CompetitorScan>> competitorScans(String brandId) async => [
    for (final s
        in await _send('GET', '/brands/$brandId/competitors/scans') as List)
      CompetitorScan.fromJson(s),
  ];
}
