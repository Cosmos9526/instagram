/// Post types the backend understands, with their Persian labels.
const postTypes = <String, String>{
  'educational': 'آموزشی',
  'news': 'خبری',
  'promo': 'تبلیغاتی',
  'sales': 'فروش',
  'video_prompt': 'پرامپت ویدیو',
};

const statusLabels = <String, String>{
  'queued': 'در صف',
  'running': 'در حال ساخت',
  'ready': 'منتظر تأیید',
  'approved': 'تأیید شده',
  'rejected': 'رد شده',
  'failed': 'ناموفق',
};

/// Python weekday numbers (0 = Monday) in Persian week order.
const weekDays = <(String, String)>[
  ('5', 'شنبه'),
  ('6', 'یکشنبه'),
  ('0', 'دوشنبه'),
  ('1', 'سه‌شنبه'),
  ('2', 'چهارشنبه'),
  ('3', 'پنجشنبه'),
  ('4', 'جمعه'),
];

List<String> _strings(dynamic v) => [for (final e in (v as List? ?? const [])) '$e'];

class Product {
  Product({this.name = '', this.desc = '', this.price = ''});
  String name, desc, price;

  factory Product.fromJson(Map<String, dynamic> j) =>
      Product(name: '${j['name'] ?? ''}', desc: '${j['desc'] ?? ''}', price: '${j['price'] ?? ''}');

  Map<String, dynamic> toJson() => {'name': name, 'desc': desc, if (price.isNotEmpty) 'price': price};
}

class Brand {
  Brand({
    this.id,
    this.name = '',
    this.industry = '',
    this.language = 'fa',
    this.description = '',
    List<Product>? products,
    this.audience = '',
    this.tone = '',
    Map<String, String>? colors,
    List<String>? forbiddenTopics,
    this.cta = '',
    List<String>? hashtags,
    Map<String, List<String>>? weeklyPlan,
  })  : products = products ?? [],
        colors = colors ?? {'primary': '#0E7C66', 'secondary': '#F4B400', 'bg': '#FFFFFF', 'text': '#111111'},
        forbiddenTopics = forbiddenTopics ?? [],
        hashtags = hashtags ?? [],
        weeklyPlan = weeklyPlan ?? {};

  String? id;
  String name, industry, language, description, audience, tone, cta;
  List<Product> products;
  Map<String, String> colors;
  List<String> forbiddenTopics, hashtags;

  /// weekday -> entries like "educational", "educational:carousel", "video_prompt"
  Map<String, List<String>> weeklyPlan;

  factory Brand.fromJson(Map<String, dynamic> j) => Brand(
        id: j['id'] as String?,
        name: '${j['name'] ?? ''}',
        industry: '${j['industry'] ?? ''}',
        language: '${j['language'] ?? 'fa'}',
        description: '${j['description'] ?? ''}',
        products: [for (final p in (j['products'] as List? ?? const [])) Product.fromJson(p)],
        audience: '${j['audience'] ?? ''}',
        tone: '${j['tone'] ?? ''}',
        colors: {for (final e in (j['colors'] as Map? ?? {}).entries) '${e.key}': '${e.value}'},
        forbiddenTopics: _strings(j['forbidden_topics']),
        cta: '${j['cta'] ?? ''}',
        hashtags: _strings(j['hashtags']),
        weeklyPlan: {
          for (final e in (j['weekly_plan'] as Map? ?? {}).entries) '${e.key}': _strings(e.value)
        },
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'industry': industry,
        'language': language,
        'description': description,
        'products': [for (final p in products) p.toJson()],
        'audience': audience,
        'tone': tone,
        'colors': colors,
        'forbidden_topics': forbiddenTopics,
        'cta': cta,
        'hashtags': hashtags,
        'weekly_plan': weeklyPlan,
      };
}

class Post {
  Post({
    required this.id,
    required this.postType,
    required this.mode,
    required this.status,
    required this.content,
    required this.slides,
    required this.error,
    required this.forDate,
  });

  final String id, postType, mode, status, error, forDate;
  final Map<String, dynamic> content;
  final List<String> slides;

  bool get isBusy => status == 'queued' || status == 'running';
  bool get isVideo => postType == 'video_prompt';

  String get title {
    final c = content;
    final slots = c['slots'] as Map?;
    final cover = c['cover'] as Map?;
    return '${slots?['headline'] ?? cover?['headline'] ?? c['title'] ?? postTypes[postType] ?? ''}';
  }

  String get caption => '${content['caption'] ?? ''}';
  List<String> get hashtags => _strings(content['hashtags']);
  String get captionWithTags =>
      [caption, if (hashtags.isNotEmpty) hashtags.map((h) => '#${h.replaceAll(' ', '_')}').join(' ')]
          .join('\n\n');

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        postType: '${j['post_type']}',
        mode: '${j['mode']}',
        status: '${j['status']}',
        content: Map<String, dynamic>.from(j['content'] as Map? ?? {}),
        slides: _strings(j['slides']),
        error: '${j['error'] ?? ''}',
        forDate: '${j['for_date'] ?? ''}',
      );
}

class GenerateRequest {
  GenerateRequest({
    required this.postType,
    this.mode = 'single',
    this.topicHint = '',
    this.nBody = 4,
    this.targetSeconds = 24,
  });

  String postType, mode, topicHint;
  int nBody, targetSeconds;

  Map<String, dynamic> toJson() => {
        'post_type': postType,
        'mode': postType == 'video_prompt' ? 'video' : mode,
        'topic_hint': topicHint,
        'n_body': nBody,
        'target_seconds': targetSeconds,
      };
}
