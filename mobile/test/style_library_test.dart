import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:postyar/api.dart';
import 'package:postyar/models.dart';
import 'package:postyar/screens/style_library_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('custom Persian brief is copied completely and returned to Create', (
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
    api.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'templates': [],
          'video_styles': [],
          'prompt_styles': [
            {
              'id': 'v',
              'kind': 'video',
              'name_en': 'Cinematic',
              'name_fa': 'سینمایی',
              'description': 'Dramatic light',
              'video_style': 'cinematic_product',
              'prompt':
                  '10 seconds {{brand}}\n{{brief}}\n8-second scene + 2-second end card',
              'cover_prompt': 'Cover {{brand}} {{brief}}',
              'provenance': 'Original Rahboom template',
            },
            {
              'id': 'i',
              'kind': 'image',
              'name_en': 'Studio',
              'name_fa': 'استودیویی',
              'description': 'Soft studio light',
              'prompt': 'Image {{brief}}',
              'cover_prompt': 'Cover {{brief}}',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    StyleSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<StyleSelection>(
                  MaterialPageRoute(
                    builder: (_) => StyleLibraryScreen(
                      api: api,
                      brand: Brand(name: 'Rahboom'),
                    ),
                  ),
                );
              },
              child: const Text('Open library'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cinematic'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Copy complete prompt'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byType(TextField).first,
      'رها می‌گوید: این ابزار را ببین.',
    );
    await tester.pumpAndSettle();
    const expected =
        '10 seconds Rahboom\nرها می‌گوید: این ابزار را ببین.\n8-second scene + 2-second end card';
    await tester.ensureVisible(find.text('Copy complete prompt'));
    await tester.tap(find.text('Copy complete prompt'));
    await tester.pumpAndSettle();
    expect(copied, expected);
    await tester.ensureVisible(find.text('Copy cover prompt'));
    await tester.tap(find.text('Copy cover prompt'));
    await tester.pumpAndSettle();
    expect(copied, 'Cover Rahboom رها می‌گوید: این ابزار را ببین.');
    await tester.ensureVisible(find.text('Use in Create'));
    await tester.tap(find.text('Use in Create'));
    await tester.pumpAndSettle();
    expect(result?.prompt, expected);
    expect(result?.style.videoStyle, 'cinematic_product');
    expect(tester.takeException(), isNull);
  });
}
