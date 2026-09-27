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
  final List<(TextEditingController, TextEditingController)> _products = [
    (TextEditingController(), TextEditingController()),
  ];
  List<String> _industry = [], _audience = [], _tone = [], _cta = [], _forbidden = ['سیاست', 'مذهب'];
  String _language = 'fa';
  int _palette = 0;
  int _plan = 1;

  static const _titles = [
    ('کسب‌وکارت چیه؟', 'اسم و حوزه‌ی کاری'),
    ('چی می‌فروشی؟', 'محصولات یا خدماتی که می‌خواهی درباره‌شان پست بسازیم'),
    ('مشتری‌هات کی‌اند؟', 'مخاطب و لحن حرف زدن با او'),
    ('قوانین پست‌ها', 'جمله‌ی آخر پست‌ها و موضوعاتی که ممنوع است'),
    ('رنگ برند', 'اسلایدها با این رنگ‌ها ساخته می‌شوند'),
    ('هر چند وقت یک پست؟', 'بعداً از تنظیمات قابل تغییر است'),
  ];

  String? _stepError() => switch (_step) {
    0 when _name.text.trim().isEmpty => 'اسم کسب‌وکار را بنویسید',
    0 when _industry.isEmpty => 'حوزه‌ی کاری را انتخاب کنید',
    1 when _products.every((p) => p.$1.text.trim().isEmpty) => 'حداقل یک محصول یا خدمت بنویسید',
    _ => null,
  };

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
    final p = brandPalettes[_palette];
    final brand = Brand(
      name: _name.text.trim(),
      industry: _industry.first,
      language: _language,
      website: _website.text.trim(),
      instagram: _instagram.text.trim().replaceFirst('@', ''),
      products: [
        for (final (n, d) in _products)
          if (n.text.trim().isNotEmpty) Product(name: n.text.trim(), desc: d.text.trim()),
      ],
      audience: _audience.join('، '),
      tone: _tone.join('، '),
      cta: _cta.isEmpty ? '' : _cta.first,
      forbiddenTopics: _forbidden,
      colors: {'primary': p[0], 'secondary': p[1], 'bg': p[2], 'text': p[3]},
      weeklyPlan: _plans[_plan].$3,
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
    0 => [
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
    1 => [
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
        controller: _website,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'وب‌سایت (اختیاری)', hintText: 'https://'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _instagram,
        textDirection: TextDirection.ltr,
        decoration: const InputDecoration(labelText: 'آیدی اینستاگرام (اختیاری)', hintText: 'mybrand'),
      ),
    ],
    2 => [
      ChoiceField(
        label: 'مخاطب',
        help: 'هر چند مورد',
        options: audienceOptions,
        values: _audience,
        onChanged: (v) => setState(() => _audience = v),
      ),
      ChoiceField(label: 'لحن', options: toneOptions, values: _tone, onChanged: (v) => setState(() => _tone = v)),
    ],
    3 => [
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
    4 => [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
        children: [
          for (var k = 0; k < brandPalettes.length; k++)
            _PaletteCard(p: brandPalettes[k], selected: k == _palette, onTap: () => setState(() => _palette = k)),
        ],
      ),
    ],
    _ => [
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
