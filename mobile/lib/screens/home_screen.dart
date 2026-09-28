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
    final now = DateTime.now();
    final weekday = now.weekday - 1; // Python convention used by the weekly plan: 0 = Monday
    final today = widget.brand.weeklyPlan['$weekday'] ?? const <String>[];
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
          HeroCard(
            title: 'امروز چی منتشر کنیم؟',
            subtitle: today.isEmpty
                ? '${_weekdaysFa[weekday]} در برنامه‌ی هفتگی خالی است؛ یکی از ایده‌های پایین را بساز.'
                : '${_weekdaysFa[weekday]} طبق برنامه‌ی هفتگی:',
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
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: PColors.violet),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF2E1065), fontWeight: FontWeight.w900),
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
