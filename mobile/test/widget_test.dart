import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postyar/api.dart';
import 'package:postyar/main.dart';
import 'package:postyar/models.dart';
import 'package:postyar/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('video posts expose their editorial label', () {
    final news = Post.fromJson({
      'id': 'n',
      'post_type': 'video_prompt',
      'content': {'content_label': 'news', 'title': 'خبر امروز'},
    });
    final trend = Post.fromJson({
      'id': 't',
      'post_type': 'video_prompt',
      'content': {'content_label': 'trending', 'title': 'ترند امروز'},
    });
    expect(news.contentLabel, 'News');
    expect(trend.contentLabel, 'Trending');
  });

  test('brand json round-trip keeps weekly plan, products and links', () {
    final b = Brand(
      name: 'کافه',
      industry: 'قهوه',
      website: 'https://x.ir',
      products: [Product(name: 'اسپرسو', desc: 'تازه')],
      weeklyPlan: {
        '5': ['educational:carousel'],
      },
    );
    final back = Brand.fromJson({'id': 'x', ...b.toJson()});
    expect(back.weeklyPlan['5'], ['educational:carousel']);
    expect(back.products.single.name, 'اسپرسو');
    expect(back.website, 'https://x.ir');
  });

  test('post caption joins hashtags', () {
    final p = Post.fromJson({
      'id': '1',
      'post_type': 'promo',
      'mode': 'single',
      'status': 'ready',
      'error': '',
      'content': {
        'caption': 'سلام',
        'hashtags': ['کافه نمونه'],
        'slots': {'headline': 'تیتر'},
      },
      'slides': ['/media/a.png'],
    });
    expect(p.title, 'تیتر');
    expect(p.captionWithTags, 'سلام\n\n#کافه_نمونه');
  });

  test('generate request only sends the options that apply', () {
    final video = GenerateRequest(
      postType: 'video_prompt',
      mode: 'carousel',
      template: 'faq',
      videoStyle: 'pov',
    ).toJson();
    expect(video['mode'], 'video');
    expect(video.containsKey('template'), isFalse);
    expect(video['video_style'], 'pov');
    final single = GenerateRequest(
      postType: 'educational',
      template: 'faq',
      videoStyle: 'pov',
    ).toJson();
    expect(single['template'], 'faq');
    expect(single.containsKey('video_style'), isFalse);
  });

  test('research report accessors', () {
    final r = Research.fromJson({
      'id': 'r',
      'status': 'ready',
      'report': {
        'keywords': ['a'],
        'trends': [
          {'title': 't'},
        ],
        'ran': {'web': 'web'},
      },
    });
    expect(r.keywords, ['a']);
    expect(r.trends.single['title'], 't');
    expect(r.isBusy, isFalse);
  });

  test('market alert parses urgency and source timestamps', () {
    final alert = MarketAlert.fromJson({
      'id': 'a',
      'title': 'Claude Pro pricing changed',
      'source': 'Anthropic',
      'importance': 5,
      'category': 'pricing',
      'published_at': '2026-09-30T12:00:00Z',
    });
    expect(alert.importance, 5);
    expect(alert.category, 'pricing');
    expect(alert.publishedAt?.isUtc, isTrue);
  });

  test('faDigits', () => expect(faDigits('2/5'), '۲/۵'));

  testWidgets('logged-out app opens the login screen in English and LTR', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'base_url': 'https://s'});
    final api = await Api.load();
    await tester.pumpWidget(PostyarApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Sign up'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Sign up'))),
      TextDirection.ltr,
    );
  });
}
