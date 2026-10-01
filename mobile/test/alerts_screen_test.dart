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
      String? generatedPath;
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
            request.url.path.endsWith('/alerts/0/prompt')) {
          generatedPath = request.url.path;
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
      expect(generatedPath, '/brands/rahboom/alerts/0/prompt');
      expect(find.text('News prompt'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('social platform filter keeps source and safe prompt', (tester) async {
    SharedPreferences.setMockInitialValues({'base_url': 'https://example.test', 'token': 'token'});
    final api = await Api.load();
    final rows = [
      {'id': 'ig', 'title': 'Instagram AI tutorial', 'category': 'instagram', 'source': 'Instagram', 'summary': '120 likes. Publication date unverified.', 'url': 'https://instagram.com/reel/abc/', 'verification': 'social_snapshot'},
      {'id': 'yt', 'title': 'YouTube AI tutorial', 'category': 'youtube', 'source': 'YouTube', 'summary': '9000 views', 'url': 'https://youtube.com/watch?v=abcdefghijk', 'verification': 'social_snapshot'},
      {'id': 'news', 'title': 'Other news', 'category': 'news'},
    ];
    api.client = MockClient((request) async => http.Response(jsonEncode(rows), 200));
    await tester.pumpWidget(MaterialApp(home: AlertsScreen(api: api, brand: Brand(id: 'rahboom', name: 'Rahboom'), category: 'social')));
    await tester.pumpAndSettle();
    expect(find.text('Instagram AI tutorial'), findsOneWidget);
    expect(find.text('Other news'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
    await tester.pumpAndSettle();
    expect(find.text('Instagram AI tutorial'), findsNothing);
    expect(find.text('YouTube AI tutorial'), findsOneWidget);
    final topic = newsVideoTopic(MarketAlert.fromJson(rows.first));
    expect(topic, contains('not verified news or proof of virality'));
    expect(topic, contains('https://instagram.com/reel/abc/'));
    expect(tester.takeException(), isNull);
  });

}
