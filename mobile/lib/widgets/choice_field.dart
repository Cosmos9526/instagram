import 'package:flutter/material.dart';

/// Pick one or more options as chips, plus "other…" to add a custom value. Custom values show as chips too.
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required this.onChanged,
    this.multi = true,
    this.help,
  });

  final String label;
  final String? help;
  final List<String> options;
  final List<String> values;
  final bool multi;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String v) {
    if (multi) {
      onChanged(values.contains(v) ? (values.toList()..remove(v)) : [...values, v]);
    } else {
      onChanged(values.contains(v) ? [] : [v]);
    }
  }

  Future<void> _addCustom(BuildContext context) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'بنویسید…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('افزودن')),
        ],
      ),
    );
    final v = text?.trim() ?? '';
    if (v.isEmpty || values.contains(v)) return;
    onChanged(multi ? [...values, v] : [v]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final custom = values.where((v) => !options.contains(v));
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (help != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(help!, style: theme.textTheme.bodySmall)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in [...options, ...custom])
                FilterChip(
                  label: Text(o),
                  selected: values.contains(o),
                  showCheckmark: multi,
                  onSelected: (_) => _toggle(o),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('مورد دیگر'),
                onPressed: () => _addCustom(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const industryOptions = [
  'کافه و رستوران', 'فروشگاه آنلاین', 'زیبایی و آرایشی', 'مد و پوشاک', 'آموزش و دوره', 'سلامت و پزشکی',
  'املاک', 'فناوری و نرم‌افزار', 'هوش مصنوعی', 'گردشگری', 'ورزش و تناسب اندام', 'خدمات مالی',
  'هنر و صنایع دستی', 'خودرو', 'خدمات حقوقی', 'مواد غذایی',
];
const audienceOptions = [
  'نوجوان‌ها (۱۳ تا ۱۷)', 'جوان‌ها (۱۸ تا ۲۴)', '۲۵ تا ۳۴ ساله‌ها', '۳۵ تا ۴۴ ساله‌ها', '۴۵ سال به بالا',
  'خانم‌ها', 'آقایان', 'دانشجوها', 'کارمندها', 'صاحبان کسب‌وکار', 'والدین', 'برنامه‌نویس‌ها',
  'علاقه‌مندان تکنولوژی', 'مشتری‌های لوکس', 'مشتری‌های اقتصادی',
];
const toneOptions = ['صمیمی', 'رسمی', 'شوخ‌طبع', 'الهام‌بخش', 'تخصصی', 'لوکس', 'پرانرژی', 'آرام', 'آموزشی'];
const ctaOptions = [
  'برای سفارش دایرکت بدید', 'لینک خرید در بیو', 'همین حالا تماس بگیرید', 'برای مشاوره‌ی رایگان پیام بدید',
  'پست رو ذخیره کن', 'برای دوستت بفرست', 'نظرت رو کامنت کن',
];
const forbiddenOptions = [
  'سیاست', 'مذهب', 'رقبا', 'اعلام قیمت', 'شایعات', 'ادعای پزشکی', 'محتوای بزرگسال', 'الکل و دخانیات', 'قمار',
];

List<String> splitList(String s) => s.split(RegExp('[،,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
