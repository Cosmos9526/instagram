import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/main.dart';
import 'package:postyar/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Api> setup({
    String? active,
    bool empty = false,
    bool expired = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
      'token': 'test-token',
      'active_brand_id': ?active,
    });
    final api = await Api.load();
    api.client = MockClient((req) async {
      if (expired) return http.Response('{}', 401);
      final Object data = switch (req.url.path) {
        '/auth/me' => {
          'id': 'u',
          'name': 'Owner',
          'email': 'owner@example.test',
        },
        '/brands' =>
          empty
              ? []
              : [
                  {'id': 'empty', 'name': '', 'industry': ''},
                  {
                    'id': 'rahboom',
                    'name': 'Rahboom',
                    'industry': 'AI subscriptions',
                    'language': 'fa',
                  },
                  {
                    'id': 'second',
                    'name': 'Second business',
                    'industry': 'Retail',
                  },
                ],
        '/catalog' => {'templates': [], 'video_styles': []},
        _ => [],
      };
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return api;
  }

  testWidgets(
    'opens dashboard directly, restores selection and switches businesses',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = await setup(active: 'second');
      await tester.pumpWidget(PostyarApp(api: api));
      await tester.pumpAndSettle();
      expect(find.text('Your content'), findsOneWidget);
      expect(find.text('Second business'), findsOneWidget);
      expect(find.byType(FloatingNav), findsOneWidget);
      await tester.tap(find.text('Second business'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahboom'));
      await tester.pumpAndSettle();
      expect(api.activeBrandId, 'rahboom');
      expect(find.text('Your content'), findsOneWidget);
      expect(find.text('Rahboom'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deleted selection falls back to a named business', (
    tester,
  ) async {
    final api = await setup(active: 'deleted');
    await tester.pumpWidget(PostyarApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Your content'), findsOneWidget);
    expect(api.activeBrandId, 'rahboom');
  });

  testWidgets('empty account can create its first business', (tester) async {
    final api = await setup(empty: true);
    await tester.pumpWidget(PostyarApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Add your first business'), findsOneWidget);
    expect(find.text('Your content'), findsNothing);
  });

  testWidgets('expired session returns to sign in and clears selection', (
    tester,
  ) async {
    final api = await setup(active: 'rahboom', expired: true);
    await tester.pumpWidget(PostyarApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(api.activeBrandId, isNull);
  });
}
