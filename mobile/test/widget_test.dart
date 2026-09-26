import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashtpa/api.dart';
import 'package:hashtpa/main.dart';
import 'package:hashtpa/models.dart';
import 'package:hashtpa/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('brand json round-trip keeps weekly plan and products', () {
    final b = Brand(
      name: 'کافه',
      industry: 'قهوه',
      products: [Product(name: 'اسپرسو', desc: 'تازه')],
      weeklyPlan: {'5': ['educational:carousel']},
    );
    final back = Brand.fromJson({'id': 'x', ...b.toJson()});
    expect(back.weeklyPlan['5'], ['educational:carousel']);
    expect(back.products.single.name, 'اسپرسو');
  });

  test('post caption joins hashtags', () {
    final p = Post.fromJson({
      'id': '1', 'post_type': 'promo', 'mode': 'single', 'status': 'ready', 'error': '',
      'content': {'caption': 'سلام', 'hashtags': ['کافه نمونه'], 'slots': {'headline': 'تیتر'}},
      'slides': ['/media/a.png'],
    });
    expect(p.title, 'تیتر');
    expect(p.captionWithTags, 'سلام\n\n#کافه_نمونه');
  });

  test('video request forces video mode', () {
    expect(GenerateRequest(postType: 'video_prompt', mode: 'carousel').toJson()['mode'], 'video');
  });

  test('faDigits', () => expect(faDigits('2/5'), '۲/۵'));

  testWidgets('unconfigured app opens the server screen in RTL', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = await Api.load();
    await tester.pumpWidget(HashtpaApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('اتصال به سرور'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('اتصال به سرور')));
    expect(dir, TextDirection.rtl);
  });
}
