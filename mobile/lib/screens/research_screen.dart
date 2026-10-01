import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'post_screen.dart';

typedef UseIdea =
    void Function({
      required String postType,
      String topic,
      String mode,
      String videoStyle,
      String contentLabel,
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
  String? _creating;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.research(widget.brand.id!),
        widget.api.alerts(widget.brand.id!),
      ]);
      final items = results[0] as List<Research>;
      final alerts = results[1] as List<MarketAlert>;
      if (!mounted) return;
      setState(() {
        _items = items;
        _alerts = alerts;
        _error = null;
      });
      _poll?.cancel();
      if (items.isNotEmpty && items.first.isBusy) {
        _poll = Timer(const Duration(seconds: 4), _load);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      if (_items?.firstOrNull?.isBusy == true) {
        _poll = Timer(const Duration(seconds: 8), _load);
      }
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

  Future<void> _create({
    required String topic,
    required String contentLabel,
    String videoStyle = '',
  }) async {
    if (_creating != null) return;
    setState(() => _creating = topic);
    try {
      final post = await widget.api.generate(
        widget.brand.id!,
        GenerateRequest(
          postType: 'video_prompt',
          mode: 'video',
          topicHint: topic,
          contentLabel: contentLabel,
          videoStyle: videoStyle,
          targetSeconds: 10,
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostScreen(api: widget.api, postId: post.id),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _creating = null);
    }
  }

  String _filter = 'News';
  String? _error;
  List<MarketAlert> _alerts = [];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final latest = items?.where((r) => r.status == 'ready').firstOrNull;
    final busy = items?.isNotEmpty == true && items!.first.isBusy;
    final failed = items?.isNotEmpty == true && items!.first.status == 'failed';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePadding(context, maxWidth: 760),
        children: [
          Text(
            'Discover your next video',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a topic. Turn it into a complete 10-second video prompt.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _focus,
            decoration: const InputDecoration(
              labelText: 'Explore a topic',
              hintText: 'Claude, video creation, AI coding…',
            ),
            onSubmitted: (_) {
              if (!busy && !_starting) _start();
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy || _starting ? null : _start,
            icon: const Icon(Icons.refresh),
            label: Text(
              busy || _starting ? 'Finding topics…' : 'Refresh research',
            ),
          ),
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ),
          if (failed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'The refresh failed. Previous results are shown below; try refreshing again.',
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in [
                'News',
                'Trends',
                'Tutorials',
                'Search demand',
              ])
                ChoiceChip(
                  label: Text(name),
                  selected: _filter == name,
                  onSelected: (_) => setState(() => _filter = name),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (items == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (latest != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Research snapshot: ${latest.report['created'] ?? latest.createdAt?.toLocal().toString().substring(0, 16) ?? 'Date unavailable'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ..._discover(latest),
          if (latest != null) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('Source status'),
              children: [
                for (final entry in latest.ran.entries)
                  ListTile(
                    dense: true,
                    title: Text(entry.key.replaceAll('_', ' ')),
                    subtitle: Text('${entry.value}'),
                  ),
                if (latest.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      latest.summary,
                      textDirection: contentDirection(latest.summary),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _discover(Research? r) {
    final cards = <Widget>[];
    final seen = <String>{};
    void add(
      String title,
      String detail,
      String url,
      String category, {
      String evidence = 'Topic idea',
      String date = '',
      String style = '',
    }) {
      if (title.trim().isEmpty || !seen.add(url.isEmpty ? title : url)) return;
      cards.add(
        _SignalCard(
          title: title,
          detail: [
            detail,
            evidence,
            date.isEmpty ? 'Publication date unavailable' : date,
          ].where((s) => s.isNotEmpty).join(' · '),
          sourceUrl: url,
          category: category,
          creating: _creating != null,
          onCreate: () => _create(
            contentLabel: category,
            videoStyle: style,
            topic:
                'Create a complete 10-second Rahboom Google Flow video (8-second Persian dialogue scene + 2-second end card), plus a separate cover prompt. Topic: $title. Context: $detail. Evidence: $evidence. Publication date: ${date.isEmpty ? 'unknown' : date}. Source: $url. Use the supplied Raha and Arian references. Do not invent facts, dates, prices or trend statistics. Treat an unsourced topic as an educational idea, never as breaking news.',
          ),
        ),
      );
    }

    List<Map<String, dynamic>> rows(String key) => [
      for (final e in (r?.dailyRadar[key] as List? ?? []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    if (_filter == 'News') {
      for (final a
          in _alerts
              .where((a) => a.category != 'social' && a.category != 'buzz')
              .take(25)) {
        add(
          a.title,
          a.summary,
          a.url,
          'news',
          evidence: '${a.source} · ${a.verification}',
          date: a.publishedAt?.toLocal().toString().substring(0, 16) ?? '',
        );
      }
      for (final n in rows('news')) {
        add(
          '${n['title'] ?? ''}',
          '${n['summary'] ?? n['snippet'] ?? ''}',
          '${n['url'] ?? ''}',
          'news',
          evidence: '${n['source'] ?? 'Source link'}',
          date: '${n['date'] ?? n['published'] ?? ''}',
        );
      }
    } else if (_filter == 'Trends') {
      for (final a
          in _alerts
              .where((a) => a.category == 'social' || a.category == 'buzz')
              .take(25)) {
        add(
          a.title,
          a.summary,
          a.url,
          'trending',
          evidence: '${a.source} · ${a.verification}',
          date: a.publishedAt?.toLocal().toString().substring(0, 16) ?? '',
        );
      }
      for (final v in [
        ...rows('videos'),
        ...?r?.instagramPosts,
        ...?r?.topVideos,
      ]) {
        final views = v['views'];
        add(
          '${v['title'] ?? ''}',
          '${v['channel'] ?? ''}${views != null ? ' · ${_compact(views)} views' : ''}',
          '${v['url'] ?? ''}',
          'trending',
          evidence: 'Social reference · trend growth not confirmed',
          date: '${v['published'] ?? v['date'] ?? ''}',
        );
      }
      for (final t in r?.trends ?? <Map<String, dynamic>>[]) {
        add(
          '${t['title'] ?? ''}',
          '${t['angle_for_brand'] ?? t['why_now'] ?? ''}',
          '${t['url'] ?? ''}',
          'trending',
          evidence: 'Suggested angle · verify before reporting',
        );
      }
    } else if (_filter == 'Tutorials') {
      for (final i in r?.ideas ?? <Map<String, dynamic>>[]) {
        if (i['post_type'] == 'news') continue;
        add(
          '${i['title'] ?? ''}',
          '${i['angle_for_brand'] ?? i['description'] ?? 'A practical takeaway for Rahboom customers.'}',
          '${i['url'] ?? ''}',
          'educational',
        );
      }
      for (final s in r?.videoStyles ?? <Map<String, dynamic>>[]) {
        add(
          '${s['pattern'] ?? ''}',
          '${s['why_it_works'] ?? ''}',
          '',
          'educational',
          style: '${s['style_id'] ?? ''}',
          evidence: 'Video technique reference',
        );
      }
    } else {
      cards.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Search signals indicate interest, not exact monthly search volume. Keywords below are suggestions, not measured trends.',
          ),
        ),
      );
      for (final s in rows('search_signals')) {
        add(
          '${s['query'] ?? ''}',
          '${s['source'] ?? 'Google'}${s['search_volume'] != null ? ' · ${s['search_volume']} searches (source estimate)' : ''}${s['growth'] != null ? ' · ${s['growth']} growth' : ''}',
          '${s['url'] ?? ''}',
          'trending',
          evidence: 'Search signal',
          date: '${s['date'] ?? ''}',
        );
      }
      if (r?.keywords.isNotEmpty == true) {
        cards.add(
          ExpansionTile(
            title: Text('Suggested keywords (${r!.keywords.length})'),
            children: [
              for (final k in r.keywords)
                ListTile(
                  title: Text(k, textDirection: contentDirection(k)),
                  trailing: const Icon(Icons.search),
                  onTap: () {
                    _focus.text = k;
                    _start();
                  },
                ),
            ],
          ),
        );
      }
    }
    if (cards.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No ${_filter.toLowerCase()} results yet. Refresh research or explore a specific topic.',
          ),
        ),
      ];
    }
    return cards;
  }

  String _compact(dynamic n) {
    final v = n is int ? n : int.tryParse('$n') ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return '$v';
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.title,
    required this.detail,
    required this.onCreate,
    this.sourceUrl = '',
    required this.category,
    this.creating = false,
  });
  final String title, detail, sourceUrl, category;
  final VoidCallback onCreate;
  final bool creating;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: TypeBadge(category)),
          const SizedBox(height: 8),
          Text(
            title,
            textDirection: contentDirection(title),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              if (sourceUrl.isNotEmpty)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(sourceUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Source'),
                ),
              TextButton.icon(
                onPressed: creating ? null : onCreate,
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: Text(creating ? 'Creating…' : 'Create 10s prompt'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
