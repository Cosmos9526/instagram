import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/alerts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keeps one signal per emerging topic', () {
    MarketAlert alert(String id, String title) => MarketAlert.fromJson({
      'id': id,
      'title': title,
      'category': 'buzz',
      'source': 'Source',
    });
    final result = distinctEmergingAlerts([
      alert('1', 'OpenAI introduces Dots'),
      alert('2', 'A closer look at ChatGPT Dots'),
      alert('3', 'Jev decision model beats Pokémon'),
    ]);
    expect(result.map((a) => a.id), ['1', '3']);
  });

  testWidgets(
    'shows 20 emerging signals and tapping one creates a trend video prompt',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'base_url': 'https://example.test',
        'token': 'token',
      });
      final api = await Api.load();
      Map<String, dynamic>? generated;
      final alerts = [
        for (var i = 0; i < 20; i++)
          {
            'id': '$i',
            'title': 'Official AI launch $i',
            'summary': 'Verified product detail $i',
            'source': 'OpenAI',
            'url': 'https://example.test/source/$i',
            'verification': 'official',
            'category': 'buzz',
            'importance': i == 0 ? 5 : 4,
            'published_at': '2026-09-30T10:00:00Z',
          },
      ];
      api.client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/alerts')) {
          return http.Response(jsonEncode(alerts), 200);
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/generate')) {
          generated = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'post-1',
              'post_type': 'video_prompt',
              'mode': 'video',
              'status': 'ready',
              'content': {
                'title': 'News prompt',
                'full_prompt': 'Complete prompt',
              },
            }),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path == '/posts/post-1') {
          return http.Response(
            jsonEncode({
              'id': 'post-1',
              'post_type': 'video_prompt',
              'mode': 'video',
              'status': 'ready',
              'content': {
                'title': 'News prompt',
                'full_prompt': 'Complete prompt',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            api: api,
            brand: Brand(id: 'rahboom', name: 'Rahboom'),
            category: 'buzz',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('20 real signals'), findsOneWidget);
      expect(find.text('Major update'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Official AI launch 0'));
      await tester.pumpAndSettle();
      expect(generated?['post_type'], 'video_prompt');
      expect(generated?['target_seconds'], 10);
      expect(generated?['content_label'], 'trending');
      expect(generated?['topic_hint'], contains('Raha and Arian'));
      expect(generated?['topic_hint'], contains('Source URL'));
      expect(find.text('News prompt'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
