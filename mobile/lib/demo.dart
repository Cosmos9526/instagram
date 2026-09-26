import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'models.dart';

/// Build with `--dart-define=DEMO=true` to run without a server: this in-memory fake answers the
/// same API with sample posts. Slide images are served next to the app under `demo/`
/// (rendered by tools/make_demo_slides.py).
const isDemo = bool.fromEnvironment('DEMO');

String _today() => DateTime.now().toIso8601String().substring(0, 10);

final Map<String, dynamic> _brand = {
  'id': 'demo',
  'name': 'کافه نمونه (دمو)',
  'industry': 'کافه و قهوه‌ی تخصصی',
  'language': 'fa',
  'description': 'کافه‌ی کوچک با دانه‌ی تازه‌رُست و دم‌آوری دستی',
  'products': [
    {'name': 'دانه‌ی اسپشیالتی ۲۵۰ گرمی', 'desc': 'رُست هفتگی، اتیوپی و کلمبیا'},
    {'name': 'کارگاه دم‌آوری', 'desc': 'آموزش V60 و موکاپات، هر پنجشنبه'},
  ],
  'audience': '۲۲ تا ۳۵ ساله‌های تهران، دانشجو و کارمند',
  'tone': 'صمیمی، مؤدب، کمی شوخ',
  'colors': {'primary': '#6B3E26', 'secondary': '#F2C14E', 'bg': '#FFF8F0', 'text': '#2B1B12'},
  'forbidden_topics': ['سیاست', 'رقبا'],
  'cta': 'برای سفارش دایرکت بدید',
  'hashtags': ['کافه_نمونه', 'قهوه_تخصصی'],
  'weekly_plan': {
    '5': ['educational:carousel'],
    '6': ['news'],
    '0': ['promo'],
    '1': ['educational'],
    '2': ['sales'],
    '3': ['video_prompt'],
  },
};

const _caption =
    'قهوه‌ی خوب از دانه‌ی تازه شروع می‌شود.\nاین پست رو برای صبح‌های بعد ذخیره کن.\nبرای سفارش دایرکت بدید.';

Map<String, dynamic> _sample(String type, String mode) {
  if (type == 'video_prompt') {
    const bible =
        'A woman in her early 30s with shoulder-length straight black hair, light olive skin, '
        'dark brown eyes, slim build, wearing an olive-green wool coat over a cream knit sweater and a '
        'thin gold necklace. A small specialty coffee shop with a light oak counter, a matte black '
        'espresso machine, white tiles and a large window on the left. Soft morning light from the '
        'window, 3800K, gentle contrast. 35mm lens at chest height, slow handheld push-in, 9:16, '
        'photoreal, warm filmic color grade, shallow depth of field.';
    final clips = [
      (
        'She pushes the door open and walks to the counter, smiling.',
        'Standing at the counter, facing the camera, smiling.',
      ),
      (
        'The barista hands her a cup; she wraps both hands around it and smells the aroma.',
        'Holding the cup near her face, eyes closed.',
      ),
      (
        'She opens her eyes, takes a sip and turns toward the window light.',
        'Profile toward the window, cup at chest height, still.',
      ),
    ];
    return {
      'post_type': type,
      'mode': 'video',
      'slides': <String>[],
      'content': {
        'title': 'اولین فنجان صبح',
        'idea': 'مشتری صبح زود وارد کافه می‌شود، اولین فنجانش را می‌گیرد و روزش را با آرامش شروع می‌کند.',
        'target_seconds': 24,
        'bible_text': bible,
        'keyframe_prompt': '$bible Opening frame: she stands outside the glass door, hand on the handle.',
        'clips': [
          for (var i = 0; i < clips.length; i++)
            {
              'n': i + 1,
              'seconds': 8,
              'full_prompt':
                  '$bible\n\nSHOT ${i + 1}/3 (8s, 9:16, no cuts). '
                  '${i == 0 ? 'Start from the provided image as frame 1.' : 'Use the LAST FRAME of the previous clip as the input image; this shot continues it directly.'} '
                  'Action: ${clips[i].$1} End on a near-still hold: ${clips[i].$2}\n'
                  'Avoid: text, logos, extra people, face or outfit changes, morphing, jump cuts.',
              'voiceover': [
                'هر صبح یه شروع تازه‌ست',
                'با عطر قهوه‌ای که همین هفته رُست شده',
                'کافه نمونه؛ صبح‌ها منتظرتیم',
              ][i],
              'caption_text': ['صبح بخیر', 'تازه‌رُست', 'کافه نمونه'][i],
            },
        ],
        'music_mood': 'warm acoustic guitar, 85 bpm',
        'caption': 'صبح‌تون رو با یه فنجان واقعی شروع کنید.\nآدرس در بیو.',
        'hashtags': ['قهوه', 'صبح_بخیر', 'کافه_نمونه'],
      },
    };
  }
  final (slides, content) = switch (type) {
    'educational' when mode == 'carousel' => (
      [for (var i = 0; i < 5; i++) 'demo/edu_$i.png'],
      {
        'cover': {'headline': '۳ اشتباه رایج که طعم قهوه‌ی صبحت را خراب می‌کند'},
        'body': [],
        'cta': {},
      },
    ),
    'educational' => (
      ['demo/edu_1.png'],
      {
        'template': 'car_body',
        'slots': {'headline': 'آب جوش نریز'},
      },
    ),
    'news' => (
      ['demo/news_0.png'],
      {
        'template': 'news_flash',
        'slots': {'headline': 'دانه‌ی جدید اتیوپی رسید'},
      },
    ),
    'promo' => (
      ['demo/promo_0.png'],
      {
        'template': 'promo_hero',
        'slots': {'headline': 'صبح‌ها با یک فنجان واقعی شروع کن'},
      },
    ),
    _ => (
      ['demo/sales_0.png'],
      {
        'template': 'sales_offer',
        'slots': {'headline': 'تخفیف دانه‌ی اسپشیالتی تا پایان هفته', 'badge': '۲۰٪', 'cta': 'سفارش در دایرکت'},
      },
    ),
  };
  return {
    'post_type': type,
    'mode': mode,
    'slides': slides,
    'content': {
      ...content,
      'caption': _caption,
      'hashtags': ['قهوه', 'قهوه_تخصصی', 'کافه_نمونه'],
    },
  };
}

final List<Map<String, dynamic>> _posts = [
  for (final (i, t, m, s) in [
    (1, 'educational', 'carousel', 'ready'),
    (2, 'video_prompt', 'video', 'ready'),
    (3, 'sales', 'single', 'approved'),
    (4, 'news', 'single', 'ready'),
    (5, 'promo', 'single', 'approved'),
  ])
    {
      'id': 'p$i',
      'brand': 'demo',
      'status': s,
      'error': '',
      'for_date': i <= 3 ? _today() : '2026-09-20',
      ..._sample(t, m),
    },
];
int _next = 100;

final _brands = <Map<String, dynamic>>[
  _brand,
  {
    ..._brand,
    'id': 'demo2',
    'name': 'گالری گل رز (دمو)',
    'industry': 'گل‌فروشی',
    'colors': {'primary': '#B23A5B', 'secondary': '#F7C8D0', 'bg': '#FFF7F8', 'text': '#3A1020'},
    'products': [
      {'name': 'باکس گل', 'desc': 'ارسال همان روز'},
    ],
    'weekly_plan': {
      '5': ['promo'],
      '1': ['educational'],
      '3': ['sales'],
    },
  },
];

Research? _research;

String _yt(String q) => 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}';

Map<String, dynamic> _researchJson(String status) => {
  'id': 'r1',
  'status': status,
  'focus': '',
  'error': '',
  'created_at': DateTime.now().toIso8601String(),
  'report': status != 'ready'
      ? {}
      : {
          'summary':
              'بازار قهوه‌ی تخصصی در شهرهای بزرگ رو به رشد است و مخاطب جوان بیشتر از قبل به دم‌آوری '
              'خانگی علاقه نشان می‌دهد. رقبا بیشتر لاته‌آرت پست می‌کنند؛ فرصت اصلی شما محتوای آموزشی '
              'کوتاه و قابل ذخیره درباره‌ی دم‌آوری در خانه است.',
          'business_facts': ['نمونه: در نقشه‌ها با امتیاز ۴٫۷ از ۳۲۰ نظر ثبت شده است'],
          'competitors': [
            {
              'name': 'کافه‌ی رقیب الف',
              'what_they_post': 'ریلز لاته‌آرت و فضای کافه',
              'gap_we_can_fill': 'آموزش دم‌آوری خانگی',
            },
            {
              'name': 'رُستری ب',
              'what_they_post': 'معرفی دانه‌ها با عکس محصول',
              'gap_we_can_fill': 'داستان پشت هر دانه',
            },
          ],
          'audience_interests': ['کلدبرو تابستانی', 'انتخاب آسیاب خانگی', 'قهوه‌ی کم‌کافئین'],
          'trends': [
            {
              'title': 'کلدبرو خانگی',
              'why_now': 'گرمای هوا و جست‌وجوی رو به رشد «کلدبرو»',
              'angle_for_brand': 'آموزش ۳ مرحله‌ای کلدبرو با دانه‌ی اتیوپی',
              'post_type': 'educational',
            },
            {
              'title': 'روز جهانی قهوه (۱۰ مهر)',
              'why_now': 'چند روز مانده؛ همه درباره‌اش پست می‌گذارند',
              'angle_for_brand': 'پیشنهاد ویژه‌ی روز قهوه',
              'post_type': 'sales',
            },
          ],
          'keywords': ['قهوه تخصصی', 'کلدبرو', 'دم آوری قهوه', 'دانه قهوه تازه', 'آسیاب قهوه', 'V60'],
          'hashtags': ['قهوه', 'قهوه_تخصصی', 'کلدبرو', 'باریستا', 'کافه_گردی', 'specialtycoffee'],
          'content_ideas': [
            {'title': '۵ اشتباه در دم کردن قهوه در خانه', 'post_type': 'educational', 'format': 'carousel'},
            {'title': 'یک روز در رُستری ما', 'post_type': 'promo', 'format': 'video'},
          ],
          'top_videos': [
            {
              'platform': 'youtube',
              'title': 'آموزش کلدبرو در خانه',
              'channel': 'نمونه',
              'views': 842000,
              'url': _yt('آموزش کلدبرو'),
            },
            {
              'platform': 'youtube',
              'title': 'V60 for beginners',
              'channel': 'sample',
              'views': 1250000,
              'url': _yt('V60 beginners'),
            },
            {
              'platform': 'instagram',
              'title': 'لاته‌آرت در ۱۵ ثانیه',
              'channel': 'sample',
              'views': 390000,
              'url': _yt('latte art'),
            },
          ],
          'video_styles': [
            {
              'style_id': 'tutorial_steps',
              'pattern': 'آموزش سریع دست‌ها از نمای بالا',
              'why_it_works': 'قابل ذخیره است و در ۱۵ ثانیه ارزش می‌دهد',
              'hook_example': 'کلدبرو در ۳ قدم، بدون دستگاه',
            },
            {
              'style_id': 'asmr_detail',
              'pattern': 'صدای ریختن و آسیاب از نمای نزدیک',
              'why_it_works': 'بیننده را تا آخر نگه می‌دارد',
              'hook_example': 'صدای صبح ما',
            },
          ],
          'sources': [
            {'title': 'نمونه‌ی منبع', 'url': _yt('specialty coffee')},
          ],
          'ran': {'web': 'fake', 'youtube': 'ok', 'instagram': 'off'},
        },
};

http.Client demoClient() => MockClient((req) async {
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final path = req.url.path;
  final seg = path.split('/').where((s) => s.isNotEmpty).toList();
  final body = req.body.isEmpty ? null : jsonDecode(req.body);
  Object? out;
  if (seg.first == 'auth') {
    final user = {'id': 'u1', 'email': (body is Map ? body['email'] : null) ?? 'demo@postyar.app', 'name': 'میلاد'};
    out = seg[1] == 'me' ? user : {'token': 'demo', 'user': user};
  } else if (path == '/catalog') {
    // The catalog is published next to the demo (demo/catalog.json).
    final res = await http.get(Uri.base.resolve('demo/catalog.json'));
    return http.Response.bytes(res.bodyBytes, 200, headers: {'content-type': 'application/json'});
  } else if (path == '/brands') {
    if (req.method == 'POST') {
      _brands.add({...Map<String, dynamic>.from(body as Map), 'id': 'b${_next++}'});
      out = {'id': _brands.last['id']};
    } else {
      out = _brands;
    }
  } else if (seg.first == 'brands' && seg.length == 2) {
    final b = _brands.firstWhere((b) => b['id'] == seg[1]);
    if (req.method == 'DELETE') _brands.remove(b);
    if (req.method == 'PUT') b.addAll(Map<String, dynamic>.from(body as Map));
    out = req.method == 'GET' ? b : {'id': b['id']};
  } else if (seg.length == 3 && seg[2] == 'research') {
    if (req.method == 'POST') {
      _research = Research.fromJson(_researchJson('running'));
      Timer(const Duration(seconds: 5), () => _research = Research.fromJson(_researchJson('ready')));
      out = _researchJson('running');
    } else {
      final r = seg[1] == 'demo' ? (_research ?? Research.fromJson(_researchJson('ready'))) : _research;
      out = r == null ? [] : [_researchJson(r.status)];
    }
  } else if (path.endsWith('/posts')) {
    out = _posts.where((p) => p['brand'] == seg[1]).toList().reversed.toList();
  } else if (path.endsWith('/generate')) {
    final r = body as Map;
    final post = {
      'id': 'p${_next++}',
      'brand': seg[1],
      'status': 'running',
      'error': '',
      'for_date': _today(),
      ..._sample('${r['post_type']}', '${r['mode']}'),
    };
    _posts.add(post);
    Timer(const Duration(seconds: 4), () => post['status'] = 'ready');
    out = post;
  } else {
    final post = _posts.firstWhere((p) => p['id'] == seg[1]);
    if (req.method == 'PUT') post['content'] = (body as Map)['content'];
    if (seg.length > 2) {
      post['status'] = switch (seg[2]) {
        'approve' => 'approved',
        'reject' => 'rejected',
        _ => 'running',
      };
      if (seg[2] == 'regenerate') {
        Timer(const Duration(seconds: 4), () => post['status'] = 'ready');
      }
    }
    out = post;
  }
  return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
});
