import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'post_screen.dart';

List<MarketAlert> distinctEmergingAlerts(Iterable<MarketAlert> alerts) {
  final seen = <String>{};
  final result = <MarketAlert>[];
  for (final alert in alerts) {
    final title = alert.title.toLowerCase();
    final key = title.contains('dots')
        ? 'dots'
        : title.contains('jev')
        ? 'jev'
        : title.contains('model context protocol') ||
              RegExp(r'\bmcp\b').hasMatch(title)
        ? 'mcp'
        : title.contains('context engineering')
        ? 'context-engineering'
        : title.contains('agentic memory')
        ? 'agentic-memory'
        : title;
    if (seen.add(key)) result.add(alert);
  }
  return result;
}

bool isSocialAlert(MarketAlert alert) =>
    alert.category == 'instagram' || alert.category == 'youtube';

bool isTrendAlert(MarketAlert alert) =>
    alert.category == 'buzz' || isSocialAlert(alert);

String newsVideoTopic(MarketAlert alert) =>
    '''
${isTrendAlert(alert) ? 'FAST-RISING AI TOOL OR TECHNIQUE VIDEO FOR RAHBOOM.' : 'URGENT VERIFIED AI NEWS VIDEO FOR RAHBOOM.'}
Create one production-ready Google Flow prompt for a vertical 9:16 video lasting exactly 10 seconds: one continuous 8-second cinematic scene followed by a clean 2-second Rahboom end card. Use Raha and Arian as the recurring presenters, keep their appearance consistent, and write short natural Persian dialogue that fits the timing and explains ${isTrendAlert(alert) ? 'what this is, why people are talking about it, and one concrete use' : 'why this news matters'}. Include exact timing, shot composition, camera movement, lighting, expressions, actions, spoken Persian dialogue, ambient sound, transitions, negative constraints, and the final Rahboom cover/end-card copy. Do not invent facts, dates, prices, features, quotes, popularity metrics, or availability. Base every factual claim only on this source and clearly preserve uncertainty when the source is reporting rather than official.

${isSocialAlert(alert) ? 'This is a social discovery candidate, not verified news or proof of virality. Do not claim it is trending, growing, or from today unless the evidence explicitly supports that. Make an original Rahboom demonstration inspired by the topic; do not copy the creator’s script or claim to have watched the video. Public search metadata may be incomplete.' : ''}
Story: ${alert.title}
Summary: ${alert.summary}
Source: ${alert.source}
Published: ${alert.publishedAt?.toUtc().toIso8601String() ?? 'date unavailable'}
Source URL: ${alert.url}
'''
        .trim();

class MajorAlertBadge extends StatelessWidget {
  const MajorAlertBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE3D5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department, size: 16, color: Color(0xFFB42318)),
        SizedBox(width: 4),
        Text(
          'Major update',
          style: TextStyle(
            color: Color(0xFFB42318),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.api,
    required this.brand,
    this.category,
  });
  final Api api;
  final Brand brand;
  final String? category;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<MarketAlert>? _alerts;
  String? _error;
  String? _creatingId;
  bool _refreshing = false;
  String _platform = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final alerts = await widget.api.alerts(widget.brand.id!);
      if (!mounted) return;
      setState(() {
        _alerts = widget.category == null
            ? alerts
            : widget.category == 'social'
            ? alerts.where(isSocialAlert).toList()
            : widget.category == 'buzz'
            ? distinctEmergingAlerts(
                alerts.where((a) => a.category == widget.category),
              )
            : alerts.where((a) => a.category == widget.category).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.api.refreshAlerts(
        widget.brand.id!,
        social: widget.category == 'social',
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _create(MarketAlert alert) async {
    if (_creatingId != null) return;
    setState(() => _creatingId = alert.id);
    try {
      final post = await widget.api.generate(
        widget.brand.id!,
        GenerateRequest(
          postType: 'video_prompt',
          mode: 'video',
          topicHint: newsVideoTopic(alert),
          targetSeconds: 10,
          contentLabel: isTrendAlert(alert) ? 'trending' : 'news',
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
      if (mounted) setState(() => _creatingId = null);
    }
  }

  Future<void> _source(MarketAlert alert) async {
    final uri = Uri.tryParse(alert.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = widget.category == 'social';
    final alerts = (_alerts ?? const <MarketAlert>[])
        .where((a) => !social || _platform == 'all' || a.category == _platform)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          social
              ? 'Social trends'
              : widget.category == 'buzz'
              ? 'Emerging AI'
              : 'AI news radar',
        ),
        actions: [
          IconButton(
            tooltip: 'Check now',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: pagePadding(context, maxWidth: 760),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              social
                  ? 'AI on Instagram & YouTube'
                  : widget.category == 'buzz'
                  ? 'What people are talking about'
                  : 'Latest verified AI news',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              social
                  ? 'Recent AI posts and videos. Public search coverage is partial; engagement snapshots do not prove growth. Unknown dates are marked.'
                  : alerts.isEmpty
                  ? widget.category == 'buzz'
                        ? 'Fresh tools, techniques and ideas will appear here.'
                        : 'Fresh stories from official and credible sources.'
                  : '${alerts.length} real ${widget.category == 'buzz' ? 'signals' : 'stories'} · Tap any item to create its complete 10-second video prompt.',
            ),
            if (social) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in {
                    'all': 'All',
                    'instagram': 'Instagram',
                    'youtube': 'YouTube',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _platform == entry.key,
                      onSelected: (_) => setState(() => _platform = entry.key),
                    ),
                ],
              ),
              if (_alerts != null && alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No recent public results found for this platform. Try Check now; unavailable results are never replaced with invented trends.',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (_alerts == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Card(
                child: ListTile(
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              ),
            for (final alert in alerts)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _creatingId == null ? () => _create(alert) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isSocialAlert(alert) && alert.importance >= 5) ...[
                          const MajorAlertBadge(),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                alert.title,
                                style: Theme.of(context).textTheme.titleMedium,
                                textDirection: contentDirection(alert.title),
                              ),
                            ),
                            if (_creatingId == alert.id)
                              const Padding(
                                padding: EdgeInsets.only(left: 12),
                                child: SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.movie_creation_outlined),
                              ),
                          ],
                        ),
                        if (alert.summary.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            alert.summary,
                            maxLines: isSocialAlert(alert) ? 6 : 3,
                            overflow: TextOverflow.ellipsis,
                            textDirection: contentDirection(alert.summary),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          '${alert.verification == 'social_snapshot'
                              ? 'Discovery candidate'
                              : alert.verification == 'official'
                              ? 'Official'
                              : alert.verification == 'in_product'
                              ? 'Verified in product'
                              : 'Reported'} · ${alert.source}${alert.publishedAt == null ? '' : ' · ${DateFormat('MMM d, HH:mm').format(alert.publishedAt!.toLocal())}'}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFFB54708)),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _creatingId == alert.id
                                    ? 'Creating complete prompt…'
                                    : 'Tap to create 10s video prompt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (alert.url.isNotEmpty)
                              IconButton(
                                tooltip: 'Open source',
                                onPressed: () => _source(alert),
                                icon: const Icon(Icons.open_in_new),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
