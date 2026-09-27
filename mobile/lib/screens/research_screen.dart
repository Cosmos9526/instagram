import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

typedef UseIdea = void Function({required String postType, String topic, String mode, String videoStyle});

/// Market research: what's said online, trends, keywords, most-viewed videos and working video styles.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key, required this.api, required this.brand, required this.onUse});
  final Api api;
  final Brand brand;
  final UseIdea onUse;

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  List<Research>? _items;
  Timer? _poll;
  final _focus = TextEditingController();
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await widget.api.research(widget.brand.id!);
      if (!mounted) return;
      setState(() => _items = items);
      _poll?.cancel();
      if (items.isNotEmpty && items.first.isBusy) {
        _poll = Timer(const Duration(seconds: 4), _load);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await widget.api.startResearch(widget.brand.id!, _focus.text.trim());
      _focus.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, e.status == 409 ? 'یک تحقیق در حال انجام است' : e.message);
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    final latest = items.where((r) => r.status == 'ready').firstOrNull;
    final busy = items.isNotEmpty && items.first.isBusy;
    final failed = items.isNotEmpty && items.first.status == 'failed' ? items.first : null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('تحقیق بازار', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'جست‌وجو در اینترنت درباره‌ی کسب‌وکار و محصولاتت، ترندهای این هفته، کلمات کلیدی، '
                    'پربازدیدترین ویدیوها و سبک‌هایی که الان جواب می‌دهند. هر سه روز خودکار تکرار می‌شود.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _focus,
                    decoration: const InputDecoration(
                      labelText: 'تمرکز (اختیاری)',
                      hintText: 'مثلاً یک محصول خاص یا یک سؤال',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || _starting ? null : _start,
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.travel_explore),
                    label: Text(busy ? 'در حال تحقیق… (۱ تا ۳ دقیقه)' : 'شروع تحقیق جدید'),
                  ),
                ],
              ),
            ),
          ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'آخرین تحقیق ناموفق بود: ${failed.error}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (latest == null && !busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('هنوز تحقیقی انجام نشده.', textAlign: TextAlign.center),
            ),
          if (latest != null) ..._report(latest),
        ],
      ),
    );
  }

  List<Widget> _report(Research r) {
    final theme = Theme.of(context);
    final ran = r.ran;
    String label(String k, String v) => switch ((k, v)) {
      ('web', 'web') => 'جست‌وجوی وب',
      ('web', 'model_only') => 'بدون دسترسی وب (فقط دانش مدل)',
      ('web', 'fake') => 'نمونه',
      ('web', 'search') => 'جست‌وجوی وب و خبر',
      ('web', 'search_only') => 'جست‌وجوی وب (بدون خلاصه‌ی هوش مصنوعی)',
      ('youtube_api', _) => 'یوتیوب (API)',
      ('instagram_free', 'blocked') => 'اینستاگرام: مسدود شد',
      ('instagram_free', 'none') => 'اینستاگرام: پستی نبود',
      ('instagram_free', 'error') => 'اینستاگرام: خطا',
      ('instagram_free', _) => 'اینستاگرام: $v',
      (_, 'ok') => k == 'youtube' ? 'یوتیوب' : 'اینستاگرام',
      (_, 'error') => '${k == 'youtube' ? 'یوتیوب' : 'اینستاگرام'}: خطا',
      _ => '${k == 'youtube' ? 'یوتیوب' : 'اینستاگرام'}: غیرفعال',
    };
    return [
      SectionTitle(
        'خلاصه',
        trailing: Text(
          r.createdAt == null ? '' : faDigits(r.createdAt!.toLocal().toString().substring(0, 16)),
          style: theme.textTheme.labelSmall,
        ),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in ran.entries)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                e.value == 'ok' || e.value == 'web' ? Icons.check_circle : Icons.remove_circle_outline,
                size: 16,
              ),
              label: Text(label(e.key, '${e.value}'), style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      SelectableText(r.summary),
      if (r.trends.isNotEmpty) ...[
        const SectionTitle('ترندهای قابل استفاده'),
        for (final t in r.trends)
          _IdeaCard(
            title: '${t['title'] ?? ''}',
            lines: ['${t['why_now'] ?? ''}', 'زاویه‌ی ما: ${t['angle_for_brand'] ?? ''}'],
            action: 'ساخت پست',
            onTap: () => widget.onUse(
              postType: postTypes.containsKey(t['post_type']) ? '${t['post_type']}' : 'news',
              topic: '${t['title']} — ${t['angle_for_brand'] ?? ''}',
            ),
          ),
      ],
      if (r.videoStyles.isNotEmpty) ...[
        const SectionTitle('سبک ویدیوهایی که الان جواب می‌دهند'),
        for (final s in r.videoStyles)
          _IdeaCard(
            title: '${s['pattern'] ?? ''}',
            lines: [
              '${s['why_it_works'] ?? ''}',
              if ('${s['hook_example'] ?? ''}'.isNotEmpty) 'قلاب پیشنهادی: ${s['hook_example']}',
            ],
            action: 'پرامپت ویدیو با این سبک',
            onTap: () => widget.onUse(
              postType: 'video_prompt',
              topic: '${s['hook_example'] ?? s['pattern'] ?? ''}',
              videoStyle: '${s['style_id'] ?? ''}',
            ),
          ),
      ],
      if (r.instagramPosts.isNotEmpty) ...[
        SectionTitle('پربازدیدترین پست‌های اینستاگرام (۳ روز اخیر، ${faDigits(r.instagramPosts.length)} پست)'),
        for (final v in r.instagramPosts.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(v['type'] == 'video' ? Icons.movie_outlined : Icons.photo_outlined),
            title: Text(
              '${v['title']}'.isEmpty ? '(بدون کپشن)' : '${v['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '@${v['channel']}، ${faDigits(_compact(v['likes']))} لایک'
              '${(v['views'] ?? 0) != 0 ? '، ${faDigits(_compact(v['views']))} بازدید' : ''}، ${faDigits(_compact(v['comments']))} کامنت',
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('${v['url']}'),
          ),
      ],
      if (r.topVideos.isNotEmpty) ...[
        const SectionTitle('پربازدیدترین ویدیوهای اخیر'),
        for (final v in r.topVideos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(v['platform'] == 'instagram' ? Icons.camera_alt_outlined : Icons.smart_display_outlined),
            title: Text('${v['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${v['channel'] ?? ''}، ${faDigits(_compact(v['views']))} بازدید'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('${v['url']}'),
          ),
      ],
      if (r.keywords.isNotEmpty)
        SectionTitle(
          'کلمات کلیدی',
          trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => copyText(context, r.keywords.join('، '))),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final k in r.keywords) Chip(label: Text(k))]),
      if (r.hashtags.isNotEmpty)
        SectionTitle(
          'هشتگ‌ها',
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => copyText(context, r.hashtags.map((h) => '#$h').join(' ')),
          ),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final h in r.hashtags) Chip(label: Text('#$h'))]),
      if (r.ideas.isNotEmpty) ...[
        const SectionTitle('ایده‌های محتوا'),
        for (final i in r.ideas)
          _IdeaCard(
            title: '${i['title'] ?? ''}',
            lines: [
              '${postTypes[i['post_type']] ?? ''}، ${i['format'] == 'carousel'
                  ? 'کاروسل'
                  : i['format'] == 'video'
                  ? 'ویدیو'
                  : 'تک‌اسلاید'}',
            ],
            action: 'بساز',
            onTap: () => widget.onUse(
              postType: i['format'] == 'video'
                  ? 'video_prompt'
                  : (postTypes.containsKey(i['post_type']) ? '${i['post_type']}' : 'educational'),
              topic: '${i['title']}',
              mode: i['format'] == 'carousel' ? 'carousel' : 'single',
            ),
          ),
      ],
      if (r.competitors.isNotEmpty) ...[
        const SectionTitle('رقبا'),
        for (final c in r.competitors)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${c['name']}'),
            subtitle: Text('${c['what_they_post'] ?? ''}\nفرصت ما: ${c['gap_we_can_fill'] ?? ''}'),
          ),
      ],
      if (r.facts.isNotEmpty || r.interests.isNotEmpty) ...[
        const SectionTitle('درباره‌ی کسب‌وکار و مخاطب'),
        for (final f in [...r.facts, ...r.interests])
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $f')),
      ],
      if (r.sources.isNotEmpty) ...[
        const SectionTitle('منابع'),
        for (final s in r.sources.take(12))
          InkWell(
            onTap: () => _open('${s['url']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${s['title']}', style: TextStyle(color: theme.colorScheme.primary)),
            ),
          ),
      ],
    ];
  }

  String _compact(dynamic n) {
    final v = n is int ? n : int.tryParse('$n') ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return '$v';
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) copyText(context, url, label: 'لینک کپی شد');
    }
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.title, required this.lines, required this.action, required this.onTap});
  final String title, action;
  final List<String> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          for (final l in lines.where((l) => l.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l, style: Theme.of(context).textTheme.bodySmall),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(action),
            ),
          ),
        ],
      ),
    ),
  );
}
