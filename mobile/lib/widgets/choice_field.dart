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
      onChanged(
        values.contains(v) ? (values.toList()..remove(v)) : [...values, v],
      );
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
          decoration: const InputDecoration(hintText: 'Type here…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Add'),
          ),
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
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(help!, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in [...options, ...custom])
                FilterChip(
                  label: Text(choiceLabel(o)),
                  selected: values.contains(o),
                  showCheckmark: multi,
                  onSelected: (_) => _toggle(o),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Other'),
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
  'کافه و رستوران',
  'فروشگاه آنلاین',
  'زیبایی و آرایشی',
  'مد و پوشاک',
  'آموزش و دوره',
  'سلامت و پزشکی',
  'املاک',
  'فناوری و نرم‌افزار',
  'هوش مصنوعی',
  'گردشگری',
  'ورزش و تناسب اندام',
  'خدمات مالی',
  'هنر و صنایع دستی',
  'خودرو',
  'خدمات حقوقی',
  'مواد غذایی',
];
const audienceOptions = [
  'نوجوان‌ها (۱۳ تا ۱۷)',
  'جوان‌ها (۱۸ تا ۲۴)',
  '۲۵ تا ۳۴ ساله‌ها',
  '۳۵ تا ۴۴ ساله‌ها',
  '۴۵ سال به بالا',
  'خانم‌ها',
  'آقایان',
  'دانشجوها',
  'کارمندها',
  'صاحبان کسب‌وکار',
  'والدین',
  'برنامه‌نویس‌ها',
  'علاقه‌مندان تکنولوژی',
  'مشتری‌های لوکس',
  'مشتری‌های اقتصادی',
];
const toneOptions = [
  'صمیمی',
  'رسمی',
  'شوخ‌طبع',
  'الهام‌بخش',
  'تخصصی',
  'لوکس',
  'پرانرژی',
  'آرام',
  'آموزشی',
];
const ctaOptions = [
  'برای سفارش دایرکت بدید',
  'لینک خرید در بیو',
  'همین حالا تماس بگیرید',
  'برای مشاوره‌ی رایگان پیام بدید',
  'پست رو ذخیره کن',
  'برای دوستت بفرست',
  'نظرت رو کامنت کن',
];
const forbiddenOptions = [
  'سیاست',
  'مذهب',
  'رقبا',
  'اعلام قیمت',
  'شایعات',
  'ادعای پزشکی',
  'محتوای بزرگسال',
  'الکل و دخانیات',
  'قمار',
];

List<String> splitList(String s) => s
    .split(RegExp('[،,]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

// Translate option labels without rewriting stored brand values or Persian CTAs.
const _choiceLabels = <String, String>{
  "کافه و رستوران": "Cafe and restaurant",
  "فروشگاه آنلاین": "Online store",
  "زیبایی و آرایشی": "Beauty",
  "مد و پوشاک": "Fashion",
  "آموزش و دوره": "Education",
  "سلامت و پزشکی": "Health and wellness",
  "املاک": "Real estate",
  "فناوری و نرم‌افزار": "Technology and software",
  "هوش مصنوعی": "Artificial intelligence",
  "گردشگری": "Travel",
  "ورزش و تناسب اندام": "Fitness",
  "خدمات مالی": "Financial services",
  "هنر و صنایع دستی": "Arts and crafts",
  "خودرو": "Automotive",
  "خدمات حقوقی": "Legal services",
  "مواد غذایی": "Food",
  "نوجوان‌ها (۱۳ تا ۱۷)": "Teens (13\u201317)",
  "جوان‌ها (۱۸ تا ۲۴)": "Young adults (18\u201324)",
  "۲۵ تا ۳۴ ساله‌ها": "Ages 25\u201334",
  "۳۵ تا ۴۴ ساله‌ها": "Ages 35\u201344",
  "۴۵ سال به بالا": "Ages 45+",
  "خانم‌ها": "Women",
  "آقایان": "Men",
  "دانشجوها": "Students",
  "کارمندها": "Employees",
  "صاحبان کسب‌وکار": "Business owners",
  "والدین": "Parents",
  "برنامه‌نویس‌ها": "Developers",
  "علاقه‌مندان تکنولوژی": "Tech enthusiasts",
  "مشتری‌های لوکس": "Premium customers",
  "مشتری‌های اقتصادی": "Budget-conscious customers",
  "صمیمی": "Friendly",
  "رسمی": "Formal",
  "شوخ‌طبع": "Humorous",
  "الهام‌بخش": "Inspiring",
  "تخصصی": "Expert",
  "لوکس": "Premium",
  "پرانرژی": "Energetic",
  "آرام": "Calm",
  "آموزشی": "Educational",
  "برای سفارش دایرکت بدید": "Message us to order",
  "لینک خرید در بیو": "Shop through the link in bio",
  "همین حالا تماس بگیرید": "Call us today",
  "برای مشاوره‌ی رایگان پیام بدید": "Message us for a free consultation",
  "پست رو ذخیره کن": "Save this post",
  "برای دوستت بفرست": "Share with a friend",
  "نظرت رو کامنت کن": "Leave a comment",
  "سیاست": "Politics",
  "مذهب": "Religion",
  "رقبا": "Competitors",
  "اعلام قیمت": "Prices",
  "شایعات": "Rumors",
  "ادعای پزشکی": "Medical claims",
  "محتوای بزرگسال": "Adult content",
  "الکل و دخانیات": "Alcohol and tobacco",
  "قمار": "Gambling",
};
String choiceLabel(String value) => _choiceLabels[value] ?? value;
