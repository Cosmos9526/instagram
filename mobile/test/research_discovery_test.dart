import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/research_screen.dart';

void main() {
  testWidgets(
    'filters source-backed topics and opens a sourced video package directly',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'base_url': 'https://example.test',
      });
      final api = await Api.load();
      Map<String, dynamic>? generated;
      api.client = MockClient((req) async {
        dynamic body;
        if (req.url.path.endsWith('/research')) {
          body = [
            {
              'id': 'r',
              'status': 'ready',
              'report': {
                'daily_radar': {
                  'news': [
                    {
                      'title': 'خبر واقعی',
                      'url': 'https://source.test/news',
                      'summary': 'A confirmed feature',
                      'source': 'Official',
                    },
                  ],
                  'search_signals': [
                    {'query': 'AI video', 'source': 'Google'},
                  ],
                },
                'content_ideas': [
                  {'title': 'آموزش پرامپت', 'post_type': 'educational'},
                ],
                'instagram_posts': [
                  {
                    'title': 'مرجع اینستاگرام',
                    'url': 'https://instagram.com/p/ref',
                  },
                ],
                'keywords': ['ساخت ویدیو'],
                'ran': {'web': 'ok'},
              },
            },
          ];
        } else if (req.url.path.endsWith('/alerts')) {
          body = [];
        } else if (req.method == 'POST') {
          generated = jsonDecode(req.body) as Map<String, dynamic>;
          body = {
            'id': 'video',
            'post_type': 'video_prompt',
            'status': 'ready',
          };
        } else {
          body = {
            'id': 'video',
            'post_type': 'video_prompt',
            'status': 'ready',
            'content': {
              'output_kind': 'prompt_package',
              'full_prompt': 'Complete sourced brief',
              'cover_prompt': 'Complete cover brief',
            },
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResearchScreen(
              api: api,
              brand: Brand(id: 'b', name: 'Rahboom'),
              onUse:
                  ({
                    required postType,
                    topic = '',
                    mode = '',
                    videoStyle = '',
                    contentLabel = '',
                  }) {
                    fail('Must open directly');
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('خبر واقعی'), findsOneWidget);
      expect(find.textContaining('last 24 hours'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Trends'));
      await tester.pumpAndSettle();
      expect(find.text('مرجع اینستاگرام'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tutorials'));
      await tester.pumpAndSettle();
      expect(find.text('آموزش پرامپت'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Search demand'));
      await tester.pumpAndSettle();
      expect(find.text('AI video'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'News'));
      await tester.pumpAndSettle();
      final create = find.text('Create 10s prompt');
      await tester.ensureVisible(create);
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(generated!['post_type'], 'video_prompt');
      expect(generated!['target_seconds'], 10);
      expect(generated!['content_label'], 'news');
      expect(generated!['topic_hint'], contains('https://source.test/news'));
      expect(generated!['topic_hint'], contains('A confirmed feature'));
      expect(find.text('Complete sourced brief'), findsOneWidget);
      expect(find.text('Complete cover brief'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load failure shows retry instead of an endless spinner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
    });
    final api = await Api.load();
    api.client = MockClient((_) async => http.Response('Unavailable', 502));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchScreen(
            api: api,
            brand: Brand(id: 'b'),
            onUse:
                ({
                  required postType,
                  topic = '',
                  mode = '',
                  videoStyle = '',
                  contentLabel = '',
                }) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
