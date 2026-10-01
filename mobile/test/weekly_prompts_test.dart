import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/home_screen.dart';
import 'package:postyar/screens/prompt_package_view.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('en'));
  testWidgets('copies the whole brief exactly and keeps English direction', (
    tester,
  ) async {
    const brief =
        'GOOGLE FLOW\nRaha says: «چرا جواب کلیه؟»\n8–10 s: end card @rahboom1';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final post = Post.fromJson({
      'id': 'one',
      'post_type': 'video_prompt',
      'content': {'title': 'پرامپت امروز', 'full_prompt': brief},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PromptPackageView(post: post)),
      ),
    );
    await tester.tap(find.text('Copy full prompt'));
    await tester.pump();
    expect(copied, brief);
    expect(
      tester
          .widget<SelectableText>(
            find.byWidgetPredicate(
              (w) => w is SelectableText && w.data == brief,
            ),
          )
          .textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('each weekday opens its own prepared topic on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
    });
    final api = await Api.load();
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today;
    final posts = [
      for (var i = 0; i < 7; i++)
        {
          'id': 'day-$i',
          'post_type': 'video_prompt',
          'status': 'ready',
          'for_date': DateFormat(
            'yyyy-MM-dd',
          ).format(start.add(Duration(days: i))),
          'content': {
            'title': 'موضوع روز $i',
            'weekly_series': 'test',
            'full_prompt': 'Complete prompt $i',
            'output_kind': 'prompt_package',
          },
        },
    ];
    final openedIds = <String>[];
    api.client = MockClient((req) async {
      dynamic body;
      if (req.url.path.contains('/posts/day-')) {
        final id = req.url.path.split('/').last;
        openedIds.add(id);
        body = posts.firstWhere((p) => p['id'] == id);
      } else if (req.url.path.endsWith('/alerts')) {
        body = [];
      } else {
        body = posts;
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
          body: HomeScreen(
            api: api,
            brand: Brand(
              id: 'rahboom',
              name: 'Rahboom',
              website: 'https://rahboom.com',
            ),
            onCreate:
                ({
                  required postType,
                  topic = '',
                  mode = 'single',
                  videoStyle = '',
                  contentLabel = '',
                }) {
                  fail(
                    'A prepared day must open its prompt, not an empty creation form',
                  );
                },
            onTab: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 7; i++) {
      final label = DateFormat(
        'EEEE, MMMM d',
        'en',
      ).format(start.add(Duration(days: i)));
      final day = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );
      await tester.ensureVisible(day);
      await tester.pumpAndSettle();
      await tester.tap(day);
      await tester.pump();
      expect(find.text('موضوع روز $i'), findsOneWidget);
      final ready = find.ancestor(
        of: find.text('10 seconds · Google Flow · Ready to copy'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: ready, matching: find.text('موضوع روز $i')),
        findsOneWidget,
      );
      await tester.ensureVisible(ready);
      await tester.pumpAndSettle();
      await tester.tap(ready);
      await tester.pumpAndSettle();
      expect(find.text('Complete prompt $i'), findsOneWidget);
      expect(find.text('Copy full prompt'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(openedIds.toSet(), hasLength(7));
  });
}
