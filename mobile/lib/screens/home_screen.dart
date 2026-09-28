import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import 'post_screen.dart';
import 'posts_screen.dart';

typedef CreateCallback = void Function({required String postType, String topic, String mode, String videoStyle});

const _weekdaysFa = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

/// Project home: what to publish today (from the weekly plan), ready ideas from market and competitor
/// research, one-tap create, and the latest content.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.brand, required this.onCreate, required this.onTab});
  final Api api;
  final Brand brand;
  final CreateCallback onCreate;

  /// Switch to another project tab (2 = market, 3 = competitors).
  final ValueChanged<int> onTab;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<Post>? _posts;
  List<Map<String, dynamic>> _ideas = [];
  String? _error;
  Timer? _poll;
  DateTime _day = DateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    refresh();
    _loadIdeas();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final posts = await widget.api.posts(widget.brand.id!);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _error = null;
      });
      _poll?.cancel();
      if (posts.any((p) => p.isBusy)) _poll = Timer(const Duration(seconds: 4), refresh);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Ideas from the latest competitor scan (evidence-backed gaps first) and the latest market research.
  Future<void> _loadIdeas() async {
    final ideas = <Map<String, dynamic>>[];
    try {
      final scan = (await widget.api.competitorScans(widget.brand.id!)).where((s) => s.status == 'ready').firstOrNull;
      for (final i in scan?.postIdeas ?? const <Map<String, dynamic>>[]) {
        ideas.add({...i, 'source': 'رقبا'});
      }
    } on ApiException catch (_) {}
    try {
      final res = (await widget.api.research(widget.brand.id!)).where((r) => r.status == 'ready').firstOrNull;
      for (final t in res?.trends ?? const <Map<String, dynamic>>[]) {
        ideas.add({
          'topic': t['title'],
          'why': t['why_now'] ?? t['angle_for_brand'],
          'post_type': t['post_type'],
          'source': 'ترند',
        });
      }
      for (final i in res?.ideas ?? const <Map<String, dynamic>>[]) {
        final f = '${i['format'] ?? ''}';
        ideas.add({
          'topic': i['title'] ?? i['idea'] ?? i['topic'],
          'why': i['why'] ?? i['hook'],
          'post_type': f == 'video' ? 'video_prompt' : i['post_type'],
          if (f.isNotEmpty) 'mode': f,
          'source': 'بازار',
        });
      }
    } on ApiException catch (_) {}
    if (mounted) {
      setState(
        () => _ideas = [
          for (final i in ideas)
            if ('${i['topic'] ?? ''}'.trim().isNotEmpty) i,
        ].take(6).toList(),
      );
    }
  }

  Future<void> _open(Post p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostScreen(api: widget.api, postId: p.id),
      ),
    );
    refresh();
  }

  (String, String, String) _planItem(String raw) {
    final parts = raw.split(':');
    final type = parts.first;
    final mode = type == 'video_prompt' ? 'video' : (parts.length > 1 ? parts[1] : 'single');
    final label = type == 'video_prompt'
        ? 'پرامپت ویدیو'
        : '${mode == 'carousel' ? 'کاروسل' : 'پست'} ${postTypes[type] ?? type}';
    return (type, mode, label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = DateUtils.isSameDay(_day, DateTime.now());
    final weekday = _day.weekday - 1; // Python convention used by the weekly plan: 0 = Monday
    final today = widget.brand.weeklyPlan['$weekday'] ?? const <String>[];
    final dayLabel = '${_weekdaysFa[weekday]} ${jalaliLabel(_day)}';
    final posts = _posts;

    return RefreshIndicator(
      onRefresh: () async {
        await refresh();
        await _loadIdeas();
      },
      child: ListView(
        padding: pagePadding(context, maxWidth: 1100),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          WeekStrip(
            selected: _day,
            plan: widget.brand.weeklyPlan,
            posts: posts ?? const [],
            onSelect: (d) => setState(() => _day = d),
          ),
          const SizedBox(height: 12),
          HeroCard(
            title: isToday ? 'امروز چی منتشر کنیم؟' : 'برنامه‌ی $dayLabel',
            subtitle: today.isEmpty
                ? '$dayLabel در برنامه‌ی هفتگی خالی است؛ یکی از ایده‌های پایین را بساز.'
                : '$dayLabel طبق برنامه‌ی هفتگی:',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final raw in today)
                  Builder(
                    builder: (_) {
                      final (type, mode, label) = _planItem(raw);
                      return _HeroButton(
                        icon: type == 'video_prompt' ? Icons.movie_creation_outlined : Icons.auto_awesome,
                        label: 'ساخت $label',
                        onTap: () => widget.onCreate(postType: type, mode: mode),
                      );
                    },
                  ),
                if (today.isEmpty)
                  _HeroButton(
                    icon: Icons.auto_awesome,
                    label: 'ساخت محتوای جدید',
                    onTap: () => widget.onCreate(postType: 'educational'),
                  ),
              ],
            ),
          ),
          const SectionTitle('ساخت سریع'),
          ResponsiveGrid(
            minTile: 150,
            spacing: 10,
            children: [
              _QuickTile(
                icon: Icons.crop_portrait_rounded,
                title: 'پست تکی',
                body: 'یک اسلاید',
                onTap: () => widget.onCreate(postType: 'educational', mode: 'single'),
              ),
              _QuickTile(
                icon: Icons.view_carousel_outlined,
                title: 'کاروسل',
                body: 'چند اسلاید پشت هم',
                onTap: () => widget.onCreate(postType: 'educational', mode: 'carousel'),
              ),
              _QuickTile(
                icon: Icons.movie_creation_outlined,
                title: 'ویدیو',
                body: 'سناریو و پرامپت شات‌ها',
                onTap: () => widget.onCreate(postType: 'video_prompt', mode: 'video'),
              ),
              _QuickTile(
                icon: Icons.bolt_outlined,
                title: 'از یک خبر',
                body: 'لینک یا متن خبر را بده',
                onTap: () => widget.onCreate(postType: 'news', mode: 'single'),
              ),
            ],
          ),
          SectionTitle(
            'ایده‌های آماده',
            subtitle: 'از تحلیل رقبا و بازار',
            trailing: TextButton(onPressed: () => widget.onTab(2), child: const Text('بازار')),
          ),
          if (_ideas.isEmpty)
            EmptyState(
              icon: Icons.lightbulb_outline,
              title: 'هنوز ایده‌ای جمع نشده',
              body: 'یک بار «تحلیل بازار» یا «اسکن رقبا» را اجرا کن تا ایده‌های مخصوص این برند اینجا بیاید.',
              action: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(onPressed: () => widget.onTab(2), child: const Text('تحلیل بازار')),
                  OutlinedButton(onPressed: () => widget.onTab(3), child: const Text('اسکن رقبا')),
                ],
              ),
            )
          else
            ResponsiveGrid(
              minTile: 320,
              spacing: 10,
              children: [
                for (final idea in _ideas)
                  _IdeaCard(
                    idea: idea,
                    onCreate: () {
                      final type = '${idea['post_type'] ?? 'educational'}';
                      widget.onCreate(
                        postType: postTypes.containsKey(type) ? type : 'educational',
                        mode: '${idea['mode'] ?? (type == 'video_prompt' ? 'video' : 'single')}',
                        topic: '${idea['topic']}',
                      );
                    },
                  ),
              ],
            ),
          SectionTitle(
            'محتواهای اخیر',
            trailing: posts == null || posts.isEmpty
                ? null
                : TextButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostsScreen(api: widget.api, brand: widget.brand, standalone: true),
                        ),
                      );
                      refresh();
                    },
                    child: Text('همه (${faDigits(posts.length)})'),
                  ),
          ),
          if (posts == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
            )
          else if (posts.isEmpty)
            EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'هنوز محتوایی ساخته نشده',
              body: 'اولین پست یا ویدیو را از «ساخت سریع» بساز.',
              action: FilledButton.icon(
                onPressed: () => widget.onCreate(postType: 'educational'),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('ساخت اولین محتوا'),
              ),
            )
          else
            PostGrid(posts: posts.take(10).toList(), api: widget.api, onOpen: _open),
          const SizedBox(height: 8),
          if (posts != null && posts.isNotEmpty)
            Text(
              'روی هر کارت بزن تا متن، کپشن و پرامپت‌ها را ببینی، ویرایش کنی و تأیید کنی.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: PColors.green,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.body, required this.onTap});
  final IconData icon;
  final String title, body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              GradientIcon(icon, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea, required this.onCreate});
  final Map<String, dynamic> idea;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = '${idea['post_type'] ?? 'educational'}';
    final why = '${idea['why'] ?? ''}'.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TypeBadge(type, label: type == 'video_prompt' ? 'ویدیو' : null),
                const SizedBox(width: 6),
                Text(
                  'از ${idea['source']}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${idea['topic']}', style: theme.textTheme.titleSmall),
            if (why.isNotEmpty && why != 'null') ...[
              const SizedBox(height: 2),
              Text(why, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: onCreate,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                icon: const Icon(Icons.auto_awesome, size: 17),
                label: const Text('بساز'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _dayLetters = ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی']; // Monday first, like DateTime.weekday - 1
const _jalaliMonths = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

/// Gregorian → Jalali (year, month 1-12, day), the standard arithmetic conversion.
(int, int, int) toJalali(DateTime g) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  var gy = g.year;
  final gy2 = g.month > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + g.day + gdm[g.month - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return (jy, jm, jd);
}

String jalaliLabel(DateTime d) {
  final (_, m, day) = toJalali(d);
  return '${faDigits(day)} ${_jalaliMonths[m - 1]}';
}

/// This week (Saturday → Friday) as a strip of days: today in the reference's green badge, dots for the
/// planned posts and a count of content already made for that day.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.selected, required this.plan, required this.posts, required this.onSelect});
  final DateTime selected;
  final Map<String, List<String>> plan;
  final List<Post> posts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final saturday = today.subtract(Duration(days: (today.weekday + 1) % 7));
    final days = [for (var i = 0; i < 7; i++) saturday.add(Duration(days: i))];
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final (_, month, _) = toJalali(selected);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PColors.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Text('این هفته', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(_jalaliMonths[month - 1], style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: _DayCell(
                    letter: _dayLetters[d.weekday - 1],
                    day: toJalali(d).$3,
                    planned: (plan['${d.weekday - 1}'] ?? const []).length,
                    made: posts.where((p) => p.forDate == iso(d)).length,
                    isToday: d == today,
                    selected: d == DateUtils.dateOnly(selected),
                    onTap: () => onSelect(d),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.letter,
    required this.day,
    required this.planned,
    required this.made,
    required this.isToday,
    required this.selected,
    required this.onTap,
  });
  final String letter;
  final int day, planned, made;
  final bool isToday, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: selected ? PColors.heroGradient : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? PColors.mintStrong : Colors.transparent),
      ),
      child: Column(
        children: [
          Text(
            letter,
            style: const TextStyle(fontSize: 11.5, color: PColors.muted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Container(
            width: 30,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isToday ? PColors.forest : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              faDigits(day),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.2,
                color: isToday ? Colors.white : PColors.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < planned.clamp(0, 3); i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < made ? PColors.green : const Color(0xFFD0D5DD),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
