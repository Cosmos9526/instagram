import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/competitors_screen.dart';

void main() {
  testWidgets('opens saved price results and submits another product', (
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
    var query = 'Claude Max';
    var submitted = false;
    Map<String, dynamic> scan() => {
      'id': 'scan',
      'status': 'ready',
      'report': {
        'kind': 'price_search',
        'query': query,
        'results': [
          {
            'competitor_id': 'one',
            'status': 'not_found',
            'matches': [],
            'checked_at': '2026-09-30T03:20:00+00:00',
          },
        ],
      },
    };
    api.client = MockClient((req) async {
      Object data;
      if (req.method == 'POST') {
        query = jsonDecode(req.body)['query'];
        submitted = true;
        data = scan();
      } else if (req.url.path.endsWith('/scans')) {
        data = [scan()];
      } else {
        data = [
          {'id': 'one', 'name': 'Example', 'website': 'https://example.com'},
        ];
      }
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompetitorsScreen(
            api: api,
            brand: Brand(id: 'brand', name: 'Rahboom'),
            onUse:
                ({
                  required postType,
                  topic = '',
                  mode = 'single',
                  videoStyle = '',
                }) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Compare prices'), findsOneWidget);
    await tester.tap(find.text('Check prices'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a product name, for example Claude Max.'),
      findsOneWidget,
    );
    expect(submitted, isFalse);
    await tester.enterText(find.byType(TextField), 'Cursor');
    await tester.tap(find.text('Check prices'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(submitted, isTrue);
    expect(find.text('Results: Cursor'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'Claude Max'));
    await tester.pumpAndSettle();
    expect(find.text('Results: Claude Max'), findsOneWidget);
  });
}
