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

class AppUser {
  AppUser({required this.id, required this.email, required this.name});
  final String id, email, name;
  factory AppUser.fromJson(Map<String, dynamic> j) =>
      AppUser(id: '${j['id']}', email: '${j['email']}', name: '${j['name'] ?? ''}');
}

class TemplateInfo {
  TemplateInfo.fromJson(Map<String, dynamic> j)
    : code = '${j['code']}',
      name = '${j['name']}',
      description = '${j['description']}',
      postTypes = _strings(j['post_types']),
      carousel = j['carousel'] == true,
      preview = j['preview'] as String?;
  final String code, name, description;
  final List<String> postTypes;
  final bool carousel;
  final String? preview;
}

class VideoStyle {
  VideoStyle.fromJson(Map<String, dynamic> j)
    : id = '${j['id']}',
      name = '${j['name_fa']}',
      description = '${j['description_fa']}',
      bestFor = _strings(j['best_for']),
      beats = _strings(j['beats']);
  final String id, name, description;
  final List<String> bestFor, beats;
}

class Catalog {
  Catalog.fromJson(Map<String, dynamic> j)
    : templates = [for (final t in j['templates'] as List) TemplateInfo.fromJson(t)],
      videoStyles = [for (final s in j['video_styles'] as List) VideoStyle.fromJson(s)];
  final List<TemplateInfo> templates;
  final List<VideoStyle> videoStyles;

  List<TemplateInfo> forType(String postType) => templates.where((t) => t.postTypes.contains(postType)).toList();
  VideoStyle? style(String id) => videoStyles.where((s) => s.id == id).firstOrNull;
}

class Research {
  Research.fromJson(Map<String, dynamic> j)
    : id = '${j['id']}',
      status = '${j['status']}',
      focus = '${j['focus'] ?? ''}',
      error = '${j['error'] ?? ''}',
      report = Map<String, dynamic>.from(j['report'] as Map? ?? {}),
      createdAt = DateTime.tryParse('${j['created_at']}');
  final String id, status, focus, error;
  final Map<String, dynamic> report;
  final DateTime? createdAt;

  bool get isBusy => status == 'queued' || status == 'running';
  String get summary => '${report['summary'] ?? ''}';
  List<String> get keywords => _strings(report['keywords']);
  List<String> get hashtags => _strings(report['hashtags']);
  List<String> get facts => _strings(report['business_facts']);
  List<String> get interests => _strings(report['audience_interests']);
  List<Map<String, dynamic>> _maps(String k) => [
    for (final e in (report[k] as List? ?? const [])) Map<String, dynamic>.from(e as Map),
  ];
  List<Map<String, dynamic>> get trends => _maps('trends');
  List<Map<String, dynamic>> get competitors => _maps('competitors');
  List<Map<String, dynamic>> get ideas => _maps('content_ideas');
  List<Map<String, dynamic>> get topVideos => _maps('top_videos');
  List<Map<String, dynamic>> get instagramPosts => _maps('instagram_posts');
  List<Map<String, dynamic>> get videoStyles => _maps('video_styles');
  List<Map<String, dynamic>> get sources => _maps('sources');
  Map<String, dynamic> get ran => Map<String, dynamic>.from(report['ran'] as Map? ?? {});
}

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
    this.website = '',
    this.instagram = '',
    this.telegram = '',
    List<String>? competitors,
    List<Product>? products,
    this.audience = '',
    this.tone = '',
    Map<String, String>? colors,
    List<String>? forbiddenTopics,
    this.cta = '',
    List<String>? hashtags,
    Map<String, List<String>>? weeklyPlan,
  }) : competitors = competitors ?? [],
       products = products ?? [],
       colors = colors ?? {'primary': '#0E7C66', 'secondary': '#F4B400', 'bg': '#FFFFFF', 'text': '#111111'},
       forbiddenTopics = forbiddenTopics ?? [],
       hashtags = hashtags ?? [],
       weeklyPlan = weeklyPlan ?? {};

  String? id;
  String name, industry, language, description, website, instagram, telegram, audience, tone, cta;
  List<String> competitors;
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
    website: '${j['website'] ?? ''}',
    instagram: '${j['instagram'] ?? ''}',
    telegram: '${j['telegram'] ?? ''}',
    competitors: _strings(j['competitors']),
    products: [for (final p in (j['products'] as List? ?? const [])) Product.fromJson(p)],
    audience: '${j['audience'] ?? ''}',
    tone: '${j['tone'] ?? ''}',
    colors: {for (final e in (j['colors'] as Map? ?? {}).entries) '${e.key}': '${e.value}'},
    forbiddenTopics: _strings(j['forbidden_topics']),
    cta: '${j['cta'] ?? ''}',
    hashtags: _strings(j['hashtags']),
    weeklyPlan: {for (final e in (j['weekly_plan'] as Map? ?? {}).entries) '${e.key}': _strings(e.value)},
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'industry': industry,
    'language': language,
    'description': description,
    'website': website,
    'instagram': instagram,
    'telegram': telegram,
    'competitors': competitors,
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
      [caption, if (hashtags.isNotEmpty) hashtags.map((h) => '#${h.replaceAll(' ', '_')}').join(' ')].join('\n\n');

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
    this.template = '',
    this.videoStyle = '',
    this.nBody = 4,
    this.targetSeconds = 24,
  });

  String postType, mode, topicHint, template, videoStyle;
  int nBody, targetSeconds;

  Map<String, dynamic> toJson() => {
    'post_type': postType,
    'mode': postType == 'video_prompt' ? 'video' : mode,
    'topic_hint': topicHint,
    if (template.isNotEmpty && postType != 'video_prompt' && mode == 'single') 'template': template,
    if (videoStyle.isNotEmpty && postType == 'video_prompt') 'video_style': videoStyle,
    'n_body': nBody,
    'target_seconds': targetSeconds,
  };
}
