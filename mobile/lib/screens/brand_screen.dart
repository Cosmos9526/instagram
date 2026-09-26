import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Plan entries a user can put on a weekday.
const planOptions = <String, String>{
  'educational': 'آموزشی',
  'educational:carousel': 'آموزشی (کاروسل)',
  'news': 'خبری',
  'promo': 'تبلیغاتی',
  'promo:carousel': 'تبلیغاتی (کاروسل)',
  'sales': 'فروش',
  'video_prompt': 'پرامپت ویدیو',
};

const _palettes = <List<String>>[
  ['#0E7C66', '#F4B400', '#FFFFFF', '#111111'],
  ['#6B3E26', '#F2C14E', '#FFF8F0', '#2B1B12'],
  ['#1F3A93', '#FF6B6B', '#F7F9FC', '#0B1B3F'],
  ['#111111', '#E63946', '#FFFFFF', '#111111'],
  ['#5B2A86', '#F7B801', '#FBF7FF', '#1E0B33'],
  ['#2A9D8F', '#E76F51', '#FDFBF7', '#1D3557'],
];

Color _hex(String s) => Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));

class BrandScreen extends StatefulWidget {
  const BrandScreen({super.key, required this.api, this.brand, this.embedded = false, this.onSaved, this.onDeleted});
  final Api api;
  final Brand? brand;

  /// Embedded as a home tab (no own AppBar) instead of pushed as a page.
  final bool embedded;
  final void Function(String id)? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  final _form = GlobalKey<FormState>();
  late Brand _b;
  late Map<String, TextEditingController> _c;
  late List<(TextEditingController, TextEditingController)> _products;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(BrandScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand?.id != widget.brand?.id) _reset();
  }

  void _reset() {
    _b = widget.brand == null ? Brand() : Brand.fromJson({'id': widget.brand!.id, ...widget.brand!.toJson()});
    if (_b.weeklyPlan.isEmpty) {
      _b.weeklyPlan = {
        '5': ['educational:carousel'],
        '6': ['news'],
        '0': ['promo'],
        '1': ['educational'],
        '2': ['sales'],
        '3': ['video_prompt'],
      };
    }
    TextEditingController t(String v) => TextEditingController(text: v);
    _c = {
      'name': t(_b.name),
      'industry': t(_b.industry),
      'description': t(_b.description),
      'website': t(_b.website),
      'instagram': t(_b.instagram),
      'audience': t(_b.audience),
      'tone': t(_b.tone),
      'cta': t(_b.cta),
      'forbidden': t(_b.forbiddenTopics.join('، ')),
      'hashtags': t(_b.hashtags.join(' ')),
    };
    _products = [for (final p in _b.products) (t(p.name), t(p.desc))];
    if (_products.isEmpty) _products.add((t(''), t('')));
  }

  List<String> _split(String s, RegExp by) =>
      s.split(by).map((e) => e.trim().replaceFirst('#', '')).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _b
      ..name = _c['name']!.text.trim()
      ..industry = _c['industry']!.text.trim()
      ..description = _c['description']!.text.trim()
      ..website = _c['website']!.text.trim()
      ..instagram = _c['instagram']!.text.trim().replaceFirst('@', '')
      ..audience = _c['audience']!.text.trim()
      ..tone = _c['tone']!.text.trim()
      ..cta = _c['cta']!.text.trim()
      ..forbiddenTopics = _split(_c['forbidden']!.text, RegExp('[،,\n]'))
      ..hashtags = _split(_c['hashtags']!.text, RegExp(r'[\s،,]+'))
      ..products = [
        for (final (n, d) in _products)
          if (n.text.trim().isNotEmpty) Product(name: n.text.trim(), desc: d.text.trim()),
      ];
    setState(() => _busy = true);
    try {
      final id = await widget.api.saveBrand(_b);
      _b.id = id;
      if (!mounted) return;
      showSnack(context, 'ذخیره شد');
      widget.onSaved?.call(id);
      if (!widget.embedded) Navigator.of(context).pop(id);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {String? hint, int lines = 1, bool required = false, bool ltr = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _c[key],
          textDirection: ltr ? TextDirection.ltr : null,
          minLines: 1,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: required ? (v) => (v ?? '').trim().isEmpty ? 'الزامی است' : null : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('مشخصات'),
          _field('name', 'نام کسب‌وکار', required: true),
          _field('industry', 'حوزه‌ی کاری', hint: 'مثلاً کافه و قهوه‌ی تخصصی', required: true),
          _field('description', 'درباره‌ی کسب‌وکار', hint: 'چه کار می‌کنید و چه چیزی شما را متمایز می‌کند', lines: 4),
          _field('website', 'وب‌سایت (برای تحقیق بازار)', hint: 'https://…', ltr: true),
          _field('instagram', 'آیدی اینستاگرام', hint: 'mybrand', ltr: true),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fa', label: Text('محتوای فارسی')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {_b.language},
            onSelectionChanged: (s) => setState(() => _b.language = s.first),
          ),
          SectionTitle(
            'محصولات و خدمات',
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _products.add((TextEditingController(), TextEditingController()))),
            ),
          ),
          for (var i = 0; i < _products.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          TextField(
                            controller: _products[i].$1,
                            decoration: const InputDecoration(labelText: 'نام'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _products[i].$2,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(labelText: 'توضیح، مزیت، قیمت'),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _products.removeAt(i)),
                    ),
                  ],
                ),
              ),
            ),
          const SectionTitle('مخاطب و لحن'),
          _field('audience', 'مخاطب', hint: 'مثلاً ۲۲ تا ۳۵ ساله‌های تهران، دانشجو و کارمند', lines: 2),
          _field('tone', 'لحن', hint: 'مثلاً صمیمی، مؤدب، کمی شوخ', lines: 2),
          _field('cta', 'دعوت به اقدام', hint: 'مثلاً «برای سفارش دایرکت بدید»'),
          _field('forbidden', 'موضوعات ممنوع', hint: 'با ویرگول جدا کنید: سیاست، رقبا، …', lines: 2),
          _field('hashtags', 'هشتگ‌های ثابت', hint: 'کافه_نمونه قهوه_تخصصی'),
          const SectionTitle('رنگ‌های برند'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final p in _palettes)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setState(() => _b.colors = {'primary': p[0], 'secondary': p[1], 'bg': p[2], 'text': p[3]}),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: 2,
                        color: _b.colors['primary'] == p[0] && _b.colors['secondary'] == p[1]
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in p.take(3))
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _hex(c),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SectionTitle('برنامه‌ی هفتگی'),
          const Text('هر روز صبح پست‌های این برنامه خودکار ساخته می‌شوند.'),
          const SizedBox(height: 8),
          for (final (day, label) in weekDays)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(
                (_b.weeklyPlan[day] ?? const []).map((e) => planOptions[e] ?? e).join('، ').ifEmpty('بدون پست'),
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () => _editDay(day, label),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator())
                : const Text('ذخیره'),
          ),
          if (widget.embedded && _b.id != null) ...[
            const SizedBox(height: 32),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف این پروژه'),
            ),
          ],
        ],
      ),
    );
    if (widget.embedded) return form;
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand == null ? 'کسب‌وکار جدید' : 'ویرایش کسب‌وکار')),
      body: form,
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: Text('«${_b.name}» و همه‌ی پست‌ها و تحقیق‌هایش حذف می‌شود. این کار برگشت‌پذیر نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteBrand(_b.id!);
      widget.onDeleted?.call();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _editDay(String day, String label) async {
    final selected = {...?_b.weeklyPlan[day]};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('پست‌های $label', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in planOptions.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: selected.contains(e.key),
                        onSelected: (on) => setSheet(() => on ? selected.add(e.key) : selected.remove(e.key)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    setState(() => _b.weeklyPlan[day] = selected.toList());
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
