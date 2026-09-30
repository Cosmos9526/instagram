import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/screens/profile_screen.dart';
import 'package:postyar/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('loads and saves profile details', (tester) async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
      'token': 'token',
    });
    final api = await Api.load();
    Map<String, dynamic>? saved;
    api.client = MockClient((request) async {
      if (request.method == 'PUT') saved = jsonDecode(request.body);
      return http.Response(
        jsonEncode({
          'id': 'u1',
          'email': 'milad@rahboom.com',
          'name': request.method == 'PUT' ? saved!['name'] : 'Milad',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ProfileScreen(api: api, onLogout: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('milad@rahboom.com'), findsWidgets);
    expect(find.text('Personal details'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name',
      ),
      'Milad Bagheri',
    );
    await tester.scrollUntilVisible(
      find.text('Save changes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved?['name'], 'Milad Bagheri');
    expect(find.text('Profile saved'), findsOneWidget);
  });

  testWidgets('shows a recoverable error instead of an endless spinner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'https://example.test',
      'token': 'token',
    });
    final api = await Api.load();
    api.client = MockClient((_) async => http.Response('unavailable', 503));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ProfileScreen(api: api, onLogout: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
