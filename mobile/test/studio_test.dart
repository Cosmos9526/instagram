import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/main.dart';
import 'package:postyar/theme.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/project_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('invalid JSON is reported as a recoverable API error', () async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
    });
    final api = await Api.load();
    api.client = MockClient(
      (_) async => http.Response('<html>Unavailable</html>', 200),
    );
    await expectLater(api.brands(), throwsA(isA<ApiException>()));
  });

  testWidgets('same bottom navigation on desktop and mobile, no sidebar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
    });
    final api = await Api.load();
    api.client = MockClient((req) async {
      final body = switch (req.url.path) {
        '/catalog' => {'templates': [], 'video_styles': []},
        '/brands/test/posts' => [
          {
            'id': 'p1',
            'post_type': 'video_prompt',
            'mode': 'video',
            'status': 'ready',
            'content': {'title': 'خبر فوری', 'content_label': 'news'},
            'slides': [],
            'error': '',
            'for_date': '',
          },
        ],
        _ => [],
      };
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(PostyarApp(api: api));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Sign up'));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectScreen(
          api: api,
          brand: Brand(id: 'test', name: 'ره‌بوم', industry: 'هوش مصنوعی'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(find.text('Create video prompt'), findsOneWidget);
    final titleY = tester.getCenter(find.text('خبر فوری')).dy;
    final labelY = tester.getCenter(find.text('News')).dy;
    final statusY = tester.getCenter(find.text('Ready to review')).dy;
    expect(titleY, lessThan(labelY));
    expect((labelY - statusY).abs(), lessThan(12));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(FloatingNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
