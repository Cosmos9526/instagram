import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

typedef UseIdea =
    void Function({
      required String postType,
      String topic,
      String mode,
      String videoStyle,
    });

/// Market research: what's said online, trends, keywords, most-viewed videos and working video styles.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({
    super.key,
    required this.api,
    required this.brand,
    required this.onUse,
  });
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
        showSnack(
          context,
          e.status == 409 ? 'Research is already in progress' : e.message,
        );
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
    final failed = items.isNotEmpty && items.first.status == 'failed'
        ? items.first
        : null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pagePadding(context, maxWidth: 900),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Market research',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Find relevant news, topics, keywords, '
                    'and content references for your business. Research refreshes with your daily plan.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _focus,
                    decoration: const InputDecoration(
                      labelText: 'Focus (optional)',
                      hintText: 'A specific product or question',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || _starting ? null : _start,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore),
                    label: Text(
                      busy ? 'Researching… (1–3 minutes)' : 'Start research',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Last research failed: ${failed.error}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (latest == null && !busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No research yet.', textAlign: TextAlign.center),
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
      ('web', 'web') => 'Web search (Google)',
      ('web', 'search') => 'Web and news search',
      ('web', 'search_only') => 'Web search (without AI summary)',
      ('web', 'model_only') => 'No web access',
      ('web', 'fake') => 'Sample',
      ('instagram_search', _) => 'Instagram: ${v.replaceAll('posts', 'Post')}',
      ('instagram_pages', _) =>
        'Instagram profiles: ${v == 'blocked' ? 'Blocked' : v.replaceAll('posts', 'Post')}',
      ('google_trends', 'ok') => 'Google Trends',
      ('google_trends', _) => 'Google Trends: no results',
      ('youtube', 'ok') => 'YouTube videos',
      ('youtube_api', _) => 'YouTube (API)',
      (_, 'error') => '$k: Error',
      (_, 'off') => '$k: Off',
      _ => '$k: $v',
    };
    return [
      SectionTitle(
        'Summary',
        trailing: Text(
          r.createdAt == null
              ? ''
              : uiDigits(r.createdAt!.toLocal().toString().substring(0, 16)),
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
                e.value == 'ok' || e.value == 'web'
                    ? Icons.check_circle
                    : Icons.remove_circle_outline,
                size: 16,
              ),
              label: Text(
                label(e.key, '${e.value}'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      SelectableText(r.summary),
      if (r.trends.isNotEmpty) ...[
        const SectionTitle('Topics to explore'),
        for (final t in r.trends)
          _IdeaCard(
            title: '${t['title'] ?? ''}',
            lines: [
              '${t['why_now'] ?? ''}',
              'Your angle: ${t['angle_for_brand'] ?? ''}',
            ],
            action: 'Create post',
            onTap: () => widget.onUse(
              postType: postTypes.containsKey(t['post_type'])
                  ? '${t['post_type']}'
                  : 'news',
              topic: '${t['title']} — ${t['angle_for_brand'] ?? ''}',
            ),
          ),
      ],
      if (r.videoStyles.isNotEmpty) ...[
        const SectionTitle('Video style references'),
        for (final s in r.videoStyles)
          _IdeaCard(
            title: '${s['pattern'] ?? ''}',
            lines: [
              '${s['why_it_works'] ?? ''}',
              if ('${s['hook_example'] ?? ''}'.isNotEmpty)
                'Suggested hook: ${s['hook_example']}',
            ],
            action: 'Use this video style',
            onTap: () => widget.onUse(
              postType: 'video_prompt',
              topic: '${s['hook_example'] ?? s['pattern'] ?? ''}',
              videoStyle: '${s['style_id'] ?? ''}',
            ),
          ),
      ],
      if (r.instagramPosts.isNotEmpty) ...[
        SectionTitle(
          'Instagram search results (last 3 days, ${uiDigits(r.instagramPosts.length)} Post)',
        ),
        for (final v in r.instagramPosts.take(20))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              v['type'] == 'video'
                  ? Icons.movie_outlined
                  : Icons.photo_outlined,
            ),
            title: Text(
              '${v['title']}'.isEmpty ? '(No caption)' : '${v['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '@${v['channel']}، ${uiDigits(_compact(v['likes']))} likes'
              '${(v['views'] ?? 0) != 0 ? '، ${uiDigits(_compact(v['views']))} views' : ''}، ${uiDigits(_compact(v['comments']))} comments',
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('${v['url']}'),
          ),
      ],
      if (r.topVideos.isNotEmpty) ...[
        const SectionTitle('Recent video references'),
        for (final v in r.topVideos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              v['platform'] == 'instagram'
                  ? Icons.camera_alt_outlined
                  : Icons.smart_display_outlined,
            ),
            title: Text(
              '${v['title']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${v['channel'] ?? ''}، ${uiDigits(_compact(v['views']))} views',
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('${v['url']}'),
          ),
      ],
      if (r.keywords.isNotEmpty)
        SectionTitle(
          'Keywords',
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => copyText(context, r.keywords.join('، ')),
          ),
        ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final k in r.keywords) Chip(label: Text(k))],
      ),
      if (r.hashtags.isNotEmpty)
        SectionTitle(
          'Hashtags',
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () =>
                copyText(context, r.hashtags.map((h) => '#$h').join(' ')),
          ),
        ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final h in r.hashtags) Chip(label: Text('#$h'))],
      ),
      if (r.ideas.isNotEmpty) ...[
        const SectionTitle('Content ideas'),
        for (final i in r.ideas)
          _IdeaCard(
            title: '${i['title'] ?? ''}',
            lines: [
              '${postTypes[i['post_type']] ?? ''}، ${i['format'] == 'carousel'
                  ? 'Carousel'
                  : i['format'] == 'video'
                  ? 'Video'
                  : 'Single slide'}',
            ],
            action: 'Create',
            onTap: () => widget.onUse(
              postType: i['format'] == 'video'
                  ? 'video_prompt'
                  : (postTypes.containsKey(i['post_type'])
                        ? '${i['post_type']}'
                        : 'educational'),
              topic: '${i['title']}',
              mode: i['format'] == 'carousel' ? 'carousel' : 'single',
            ),
          ),
      ],
      if (r.competitors.isNotEmpty) ...[
        const SectionTitle('Competitors'),
        for (final c in r.competitors)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${c['name']}'),
            subtitle: Text(
              '${c['what_they_post'] ?? ''}\nYour opportunity: ${c['gap_we_can_fill'] ?? ''}',
            ),
          ),
      ],
      if (r.facts.isNotEmpty || r.interests.isNotEmpty) ...[
        const SectionTitle('Business and audience'),
        for (final f in [...r.facts, ...r.interests])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $f'),
          ),
      ],
      if (r.sources.isNotEmpty) ...[
        const SectionTitle('Sources'),
        for (final s in r.sources.take(12))
          InkWell(
            onTap: () => _open('${s['url']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${s['title']}',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
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
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) copyText(context, url, label: 'Link copied');
    }
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.title,
    required this.lines,
    required this.action,
    required this.onTap,
  });
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
