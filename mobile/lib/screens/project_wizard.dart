import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/choice_field.dart';
import '../widgets/common.dart';
import 'brand_screen.dart' show brandPalettes, hexColor;

/// Posting-frequency presets (Python weekday keys: 5 = Saturday … 4 = Friday).
const _plans = <(String, String, Map<String, List<String>>)>[
  (
    'سبک',
    '۳ پست در هفته',
    {
      '5': ['educational:carousel'],
      '1': ['promo'],
      '3': ['video_prompt'],
    },
  ),
  (
    'معمولی',
    '۵ پست در هفته',
    {
      '5': ['educational:carousel'],
      '6': ['news'],
      '0': ['promo'],
      '2': ['sales'],
      '3': ['video_prompt'],
    },
  ),
  (
    'فعال',
    'هر روز یک پست',
    {
      '5': ['educational:carousel'],
      '6': ['news'],
      '0': ['promo'],
      '1': ['educational'],
      '2': ['sales'],
      '3': ['video_prompt'],
      '4': ['promo:carousel'],
    },
  ),
];

/// New project, one question per step.
class ProjectWizard extends StatefulWidget {
  const ProjectWizard({super.key, required this.api});
  final Api api;

  @override
  State<ProjectWizard> createState() => _ProjectWizardState();
}

class _ProjectWizardState extends State<ProjectWizard> {
  final _page = PageController();
  int _step = 0;
  bool _busy = false;

  final _name = TextEditingController();
  final _website = TextEditingController();
  final _instagram = TextEditingController();
  final _telegram = TextEditingController();
  final _competitors = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _products = [
    (TextEditingController(), TextEditingController()),
  ];
  List<String> _industry = [], _audience = [], _tone = [], _cta = [], _forbidden = ['سیاست', 'مذهب'];
  String _language = 'fa';
  int _palette = 0;
  int _plan = 1;
  bool _analyzing = false;
  Map<String, dynamic>? _analysis; // result of /analyze
  List<String>? _sitePalette; // colors found on the website
  Map<String, List<String>>? _suggestedPlan;

  List<List<String>> get _palettes => [?_sitePalette, ...brandPalettes];

  static const _titles = [
    ('شروع سریع', 'آدرس سایت یا اینستاگرام را بده تا کسب‌وکارت را تحلیل کنیم و برنامه بچینیم'),
    ('کسب‌وکارت چیه؟', 'اسم و حوزه‌ی کاری'),
    ('چی می‌فروشی؟', 'محصولات یا خدماتی که می‌خواهی درباره‌شان پست بسازیم'),
    ('مشتری‌هات کی‌اند؟', 'مخاطب و لحن حرف زدن با او'),
    ('قوانین پست‌ها', 'جمله‌ی آخر پست‌ها و موضوعاتی که ممنوع است'),
    ('رنگ برند', 'اسلایدها با این رنگ‌ها ساخته می‌شوند'),
    ('هر چند وقت یک پست؟', 'بعداً از تنظیمات قابل تغییر است'),
  ];

  String? _stepError() => switch (_step) {
    1 when _name.text.trim().isEmpty => 'اسم کسب‌وکار را بنویسید',
    1 when _industry.isEmpty => 'حوزه‌ی کاری را انتخاب کنید',
    2 when _products.every((p) => p.$1.text.trim().isEmpty) => 'حداقل یک محصول یا خدمت بنویسید',
    _ => null,
  };

  Future<void> _analyze() async {
    final site = _website.text.trim(), ig = _instagram.text.trim();
    if (site.isEmpty && ig.isEmpty) return showSnack(context, 'آدرس سایت یا آیدی اینستاگرام را وارد کنید');
    FocusScope.of(context).unfocus();
    setState(() => _analyzing = true);
    try {
      final r = await widget.api.analyze(site, ig.replaceFirst('@', ''));
      final p = (r['profile'] as Map).cast<String, dynamic>();
      List<String> split(Object? v) => '${v ?? ''}'.split(RegExp('[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      setState(() {
        _analysis = r;
        if ('${p['name'] ?? ''}'.trim().isNotEmpty) _name.text = '${p['name']}'.trim();
        if (industryOptions.contains(p['industry'])) _industry = ['${p['industry']}'];
        if ('${p['website'] ?? ''}'.isNotEmpty) _website.text = '${p['website']}';
        if ('${p['instagram'] ?? ''}'.isNotEmpty) _instagram.text = '${p['instagram']}';
        if ('${p['telegram'] ?? ''}'.isNotEmpty) _telegram.text = '${p['telegram']}';
        final prods = [for (final x in (p['products'] as List? ?? [])) (x as Map)];
        if (prods.isNotEmpty) {
          _products
            ..clear()
            ..addAll([
              for (final x in prods)
                (TextEditingController(text: '${x['name'] ?? ''}'), TextEditingController(text: '${x['desc'] ?? ''}')),
            ]);
        }
        _audience = split(p['audience']);
        _tone = split(p['tone']);
        if ('${p['cta'] ?? ''}'.isNotEmpty) _cta = ['${p['cta']}'];
        _forbidden = [for (final f in (p['forbidden_topics'] as List? ?? _forbidden)) '$f'];
        final c = (p['colors'] as Map?) ?? {};
        if (c['primary'] != null) {
          _sitePalette = ['${c['primary']}', '${c['secondary']}', '${c['bg']}', '${c['text']}'];
          _palette = 0;
        }
        final plan = (p['weekly_plan'] as Map?) ?? {};
        if (plan.isNotEmpty) {
          _suggestedPlan = {for (final e in plan.entries) '${e.key}': [for (final t in e.value as List) '$t']};
          _plan = -1;
        }
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  Future<void> _next() async {
    final err = _stepError();
    if (err != null) return showSnack(context, err);
    if (_step < _titles.length - 1) return _go(_step + 1);
    await _finish();
  }

  Future<void> _finish() async {
    final p = _palettes[_palette];
    final brand = Brand(
      name: _name.text.trim(),
      industry: _industry.first,
      language: _language,
      website: _website.text.trim(),
      instagram: _instagram.text.trim().replaceFirst('@', ''),
      telegram: _telegram.text.trim().replaceAll(RegExp(r'^(https?://)?(t\.me/)?@?'), ''),
      competitors: [
        for (final c in _competitors.text.split(RegExp(r'[\s,،]+')))
          if (c.trim().isNotEmpty) c.trim().replaceFirst('@', ''),
      ],
      products: [
        for (final (n, d) in _products)
          if (n.text.trim().isNotEmpty) Product(name: n.text.trim(), desc: d.text.trim()),
      ],
      audience: _audience.join('، '),
      tone: _tone.join('، '),
      cta: _cta.isEmpty ? '' : _cta.first,
      forbiddenTopics: _forbidden,
      colors: {'primary': p[0], 'secondary': p[1], 'bg': p[2], 'text': p[3]},
      weeklyPlan: _plan < 0 ? _suggestedPlan! : _plans[_plan].$3,
    );
    setState(() => _busy = true);
    try {
      final id = await widget.api.saveBrand(brand);
      if (mounted) Navigator.of(context).pop(id);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _step == _titles.length - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_step - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پروژه‌ی جدید'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_step + 1) / _titles.length,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ),
        body: PageView(
          controller: _page,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _titles.length; i++)
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Text('مرحله‌ی ${faDigits(i + 1)} از ${faDigits(_titles.length)}', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Text(_titles[i].$1, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(_titles[i].$2, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 24),
                  ..._stepBody(i),
                ],
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (_step > 0) ...[
                OutlinedButton(onPressed: _busy ? null : () => _go(_step - 1), child: const Text('قبلی')),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _next,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(last ? 'ساخت پروژه' : 'بعدی'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepBody(int i) => switch (i) {
    0 => _quickStart(),
    1 => [
      TextField(
        controller: _name,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(labelText: 'اسم کسب‌وکار', hintText: 'مثلاً کلینیک موی آرین'),
      ),
      const SizedBox(height: 24),
      ChoiceField(
        label: 'حوزه‌ی کاری',
        options: industryOptions,
        values: _industry,
        multi: false,
        onChanged: (v) => setState(() => _industry = v),
      ),
    ],
    2 => [
      for (var k = 0; k < _products.length; k++)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _products[k].$1,
                        decoration: InputDecoration(labelText: 'محصول / خدمت ${faDigits(k + 1)}'),
                      ),
                    ),
                    if (_products.length > 1)
                      IconButton(onPressed: () => setState(() => _products.removeAt(k)), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _products[k].$2,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'یک جمله درباره‌اش (مزیت، قیمت…)'),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() => _products.add((TextEditingController(), TextEditingController()))),
        icon: const Icon(Icons.add),
        label: const Text('افزودن محصول دیگر'),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _telegram,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'کانال تلگرام (اختیاری)', hintText: 't.me/mychannel'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _competitors,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          labelText: 'پیج اینستاگرام رقبا (اختیاری)',
          hintText: 'competitor1, competitor2',
          helperText: 'برای تحقیق بازار: پست‌های اخیر و پربازدید رقبا بررسی می‌شود',
        ),
      ),
    ],
    3 => [
      ChoiceField(
        label: 'مخاطب',
        help: 'هر چند مورد',
        options: audienceOptions,
        values: _audience,
        onChanged: (v) => setState(() => _audience = v),
      ),
      ChoiceField(label: 'لحن', options: toneOptions, values: _tone, onChanged: (v) => setState(() => _tone = v)),
    ],
    4 => [
      ChoiceField(
        label: 'دعوت به اقدام',
        help: 'جمله‌ی آخر هر پست',
        options: ctaOptions,
        values: _cta,
        multi: false,
        onChanged: (v) => setState(() => _cta = v),
      ),
      ChoiceField(
        label: 'موضوعات ممنوع',
        options: forbiddenOptions,
        values: _forbidden,
        onChanged: (v) => setState(() => _forbidden = v),
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'fa', label: Text('پست‌ها فارسی')),
          ButtonSegment(value: 'en', label: Text('English')),
        ],
        selected: {_language},
        onSelectionChanged: (s) => setState(() => _language = s.first),
      ),
    ],
    5 => [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
        children: [
          for (var k = 0; k < _palettes.length; k++)
            _PaletteCard(p: _palettes[k], selected: k == _palette, onTap: () => setState(() => _palette = k)),
        ],
      ),
    ],
    _ => [
      if (_suggestedPlan != null)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: _plan < 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              width: _plan < 0 ? 2 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            onTap: () => setState(() => _plan = -1),
            leading: Icon(_plan < 0 ? Icons.radio_button_checked : Icons.radio_button_off),
            title: const Text('برنامه‌ی پیشنهادی تحلیل', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${faDigits(_suggestedPlan!.values.fold<int>(0, (a, v) => a + v.length))} پست در هفته، متناسب با کسب‌وکارت'),
          ),
        ),
      for (var k = 0; k < _plans.length; k++)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: k == _plan ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              width: k == _plan ? 2 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            onTap: () => setState(() => _plan = k),
            leading: Icon(k == _plan ? Icons.radio_button_checked : Icons.radio_button_off),
            title: Text(_plans[k].$1, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(_plans[k].$2),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'پست‌ها هر روز صبح خودکار ساخته می‌شوند و قبل از انتشار منتظر تأیید تو می‌مانند.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  };
}

extension on _ProjectWizardState {
  List<Widget> _quickStart() {
    final theme = Theme.of(context);
    final a = _analysis;
    return [
      TextField(
        controller: _website,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'وب‌سایت', hintText: 'example.ir', prefixIcon: Icon(Icons.language)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _instagram,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(
          labelText: 'آیدی اینستاگرام',
          hintText: 'mybrand',
          prefixIcon: Icon(Icons.alternate_email),
        ),
      ),
      const SizedBox(height: 8),
      Text('یکی از این دو هم کافی است.', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: _analyzing ? null : _analyze,
        icon: _analyzing
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome),
        label: Text(_analyzing ? 'در حال بررسی سایت و پیج… (تا یک دقیقه)' : 'تحلیل خودکار کسب‌وکار'),
      ),
      if (a != null) ...[
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name.text.isEmpty ? 'نتیجه‌ی تحلیل' : _name.text, style: theme.textTheme.titleMedium),
                if (_industry.isNotEmpty) Text(_industry.first, style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                for (final e in (a['evidence'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 16, color: PColors.teal),
                        const SizedBox(width: 6),
                        Expanded(child: Text('$e', style: theme.textTheme.bodySmall)),
                      ],
                    ),
                  ),
                if (_products.any((p) => p.$1.text.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in _products.take(6))
                        if (p.$1.text.isNotEmpty) Chip(label: Text(p.$1.text), visualDensity: VisualDensity.compact),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('برنامه‌ی هفته‌ی اول', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final d in (a['plan'] as List? ?? []))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text('${(d as Map)['day']}'.substring(0, 1))),
              title: Text('${d['idea']}'),
              subtitle: Text('${d['day']} · ${d['type_fa']}'),
            ),
          ),
        const SizedBox(height: 4),
        Text('همه‌چیز در مرحله‌های بعد قابل ویرایش است. «بعدی» را بزن و بررسی کن.', style: theme.textTheme.bodySmall),
      ] else ...[
        const SizedBox(height: 12),
        TextButton(onPressed: () => _go(1), child: const Text('نه، خودم دستی پر می‌کنم')),
      ],
    ];
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.p, required this.selected, required this.onTap});
  final List<String> p;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(22),
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? PColors.teal : Colors.transparent, width: 3),
      ),
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: hexColor(p[2]),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 10,
                width: 48,
                decoration: BoxDecoration(color: hexColor(p[1]), borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(height: 10),
              Text(
                'تیتر پست',
                style: TextStyle(color: hexColor(p[3]), fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: hexColor(p[0]), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  'دکمه',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
