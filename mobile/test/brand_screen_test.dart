import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/brand_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('syncs offers from sources and removes manual product entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
      'token': 'token',
    });
    final api = await Api.load();
    Map<String, dynamic>? saved;
    final requests = <String>[];
    api.client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/analyze')) {
        return http.Response(
          jsonEncode({
            'profile': {
              'name': 'Rahboom',
              'industry': 'هوش مصنوعی',
              'description': 'فروش اشتراک ابزارهای هوش مصنوعی',
              'audience': 'برنامه‌نویس‌ها و تولیدکنندگان محتوا',
              'tone': 'دقیق و کاربردی',
              'cta': 'برای انتخاب پلن پیام بده',
              'products': [
                {'name': 'Claude Max', 'desc': 'اشتراک یک ماهه'},
                {'name': 'ChatGPT Plus', 'desc': 'اشتراک شخصی'},
              ],
              'colors': {'primary': '#0E7C66', 'secondary': '#F4B400'},
            },
            'evidence': ['سایت خوانده شد: ۲ محصول'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'PUT') {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'rahboom'}), 200);
      }
      return http.Response('{}', 404);
    });
    final brand = Brand(
      id: 'rahboom',
      name: 'Rahboom',
      industry: 'هوش مصنوعی',
      website: 'https://rahboom.com',
      instagram: 'rahboomshop',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandScreen(api: api, brand: brand, embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Products and services'), findsNothing);
    expect(find.text('Weekly plan'), findsNothing);
    expect(find.text('Refresh from sources'), findsOneWidget);
    await tester.ensureVisible(find.text('Refresh from sources'));
    await tester.tap(find.text('Refresh from sources'));
    await tester.pumpAndSettle();
    expect(requests, contains('POST /analyze'));
    expect(requests, contains('PUT /brands/rahboom'));
    expect(saved, isNotNull);
    expect((saved?['products'] as List).length, 2);
    await tester.scrollUntilVisible(
      find.text('Claude Max'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Claude Max'), findsOneWidget);
    expect(find.text('ChatGPT Plus'), findsOneWidget);
    expect(find.text('سایت خوانده شد: ۲ محصول'), findsOneWidget);
    expect(saved?['audience'], 'برنامه‌نویس‌ها و تولیدکنندگان محتوا');
    expect(tester.takeException(), isNull);
  });
}
