import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/delete_post.dart';
import 'alerts_screen.dart';
import 'post_screen.dart';
import 'posts_screen.dart';

typedef CreateCallback =
    void Function({
      required String postType,
      String topic,
      String mode,
      String videoStyle,
      String contentLabel,
    });

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.brand,
    required this.onCreate,
    required this.onTab,
  });
  final Api api;
  final Brand brand;
  final CreateCallback onCreate;
  final ValueChanged<int> onTab;
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  List<Post>? _posts;
  List<MarketAlert>? _alerts;
  String? _error;
  Timer? _poll;
  bool _preparingWeek = false;
  bool _checkingAlerts = false;
  String? _creatingAlertId;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        widget.api.posts(widget.brand.id!),
        widget.api.alerts(widget.brand.id!),
      ]);
      final posts = results[0] as List<Post>;
      final alerts = results[1] as List<MarketAlert>;
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _alerts = alerts;
        _error = null;
      });
      _poll?.cancel();
      if (posts.any((p) => p.isBusy)) {
        _poll = Timer(const Duration(seconds: 4), refresh);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _refreshAlerts() async {
    setState(() => _checkingAlerts = true);
    try {
      final added = await widget.api.refreshAlerts(widget.brand.id!);
      final alerts = await widget.api.alerts(widget.brand.id!);
      if (!mounted) return;
      setState(() => _alerts = alerts);
      showSnack(
        context,
        added == 0
            ? 'No new important alerts'
            : '$added new important alert${added == 1 ? '' : 's'}',
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _checkingAlerts = false);
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

  Future<void> _openAlerts({String? category}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlertsScreen(
          api: widget.api,
          brand: widget.brand,
          category: category,
        ),
      ),
    );
    refresh();
  }

  Future<void> _generateAlert(MarketAlert alert) async {
    if (_creatingAlertId != null) return;
    setState(() => _creatingAlertId = alert.id);
    try {
      final post = await widget.api.generate(
        widget.brand.id!,
        GenerateRequest(
          postType: 'video_prompt',
          mode: 'video',
          topicHint: newsVideoTopic(alert),
          targetSeconds: 10,
          contentLabel: alert.category == 'buzz' ? 'trending' : 'news',
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostScreen(api: widget.api, postId: post.id),
        ),
      );
      await refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _creatingAlertId = null);
    }
  }

  Future<void> _prepareWeek() async {
    setState(() => _preparingWeek = true);
    try {
      await widget.api.prepareWeek(widget.brand.id!);
      await refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _preparingWeek = false);
    }
  }

  Future<void> _remove(Post p) async {
    if (!await deletePost(context, widget.api, p)) return;
    await refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Content deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await widget.api.review(p.id, 'restore');
              await refresh();
            } on ApiException catch (e) {
              if (mounted) showSnack(context, e.message);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(
      padding: pagePadding(context, maxWidth: 760),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Text('Your content', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        _breakingAlerts(context),
        const SizedBox(height: 12),
        if (_alerts == null || _alerts!.any((a) => a.category == 'buzz')) ...[
          _buzzing(context),
          const SizedBox(height: 12),
        ],
        _weeklyPlan(context),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () =>
              widget.onCreate(postType: 'video_prompt', mode: 'video'),
          icon: const Icon(Icons.movie_creation_outlined),
          label: const Text('Create video prompt'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('Saved content')),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostsScreen(
                      api: widget.api,
                      brand: widget.brand,
                      standalone: true,
                    ),
                  ),
                );
                refresh();
              },
              child: const Text('View all'),
            ),
          ],
        ),
        if (_error != null)
          Row(
            children: [
              Expanded(child: Text(_error!)),
              TextButton(onPressed: refresh, child: const Text('Retry')),
            ],
          ),
        if (_posts == null && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_posts?.isEmpty == true)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Your video prompts will appear here.'),
          ),
        for (final p in (_posts ?? <Post>[]).take(20))
          Card(
            child: ListTile(
              onTap: () => _open(p),
              leading: Icon(
                p.isVideo ? Icons.movie_outlined : Icons.description_outlined,
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    textDirection: contentDirection(p.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TypeBadge(switch (p.contentLabel) {
                        'Sales' => 'sales',
                        'Promotional' => 'promo',
                        'News' => 'news',
                        'Educational' => 'educational',
                        'Trending' => 'trending',
                        _ => 'video_prompt',
                      }, label: p.contentLabel),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          p.isBusy
                              ? 'Creating…'
                              : p.status == 'failed'
                              ? 'Needs retry'
                              : p.status == 'approved'
                              ? 'Approved'
                              : 'Ready to review',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Delete',
                onPressed: p.isBusy ? null : () => _remove(p),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _breakingAlerts(BuildContext context) {
    final alerts = (_alerts ?? const <MarketAlert>[])
        .where((a) => a.category != 'buzz')
        .toList();
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFFFF4ED),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: Color(0xFFB54708),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Urgent AI alerts',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Check now',
                  onPressed: _checkingAlerts ? null : _refreshAlerts,
                  icon: _checkingAlerts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                ),
                TextButton(
                  onPressed: alerts.isEmpty ? null : _openAlerts,
                  child: Text(
                    'View all${alerts.isEmpty ? '' : ' (${alerts.length})'}',
                  ),
                ),
              ],
            ),
            const Text(
              'Important launches, pricing and plan changes — checked every 3 hours.',
            ),
            if (_alerts == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No important alert found yet. Tap Check now for a fresh scan.',
                ),
              )
            else
              for (final alert in alerts.take(3)) _alertPreview(alert, theme),
          ],
        ),
      ),
    );
  }

  Widget _alertPreview(MarketAlert alert, ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 20),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _creatingAlertId == null ? () => _generateAlert(alert) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (alert.importance >= 5) ...[
                const MajorAlertBadge(),
                const SizedBox(height: 6),
              ],
              Text(
                alert.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
                textDirection: contentDirection(alert.title),
              ),
              const SizedBox(height: 4),
              Text(
                '${alert.verification == 'official'
                    ? 'Official'
                    : alert.verification == 'in_product'
                    ? 'Verified in product'
                    : 'Reported'} · ${alert.source}${alert.publishedAt == null ? '' : ' · ${DateFormat('MMM d, HH:mm').format(alert.publishedAt!.toLocal())}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB54708),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton.icon(
                    onPressed: _creatingAlertId == null
                        ? () => _generateAlert(alert)
                        : null,
                    icon: _creatingAlertId == alert.id
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.movie_creation_outlined, size: 18),
                    label: Text(
                      _creatingAlertId == alert.id
                          ? 'Creating…'
                          : 'Create 10s video',
                    ),
                  ),
                  if (alert.url.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(alert.url);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('Source'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buzzing(BuildContext context) {
    final items = (_alerts ?? const <MarketAlert>[])
        .where((a) => a.category == 'buzz')
        .toList();
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFF2F0FF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: Color(0xFF6941C6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Emerging AI',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: items.isEmpty
                      ? null
                      : () => _openAlerts(category: 'buzz'),
                  child: Text(
                    'View all${items.isEmpty ? '' : ' (${items.length})'}',
                  ),
                ),
              ],
            ),
            const Text(
              'Fast-rising tools, techniques and ideas people are talking about.',
            ),
            if (_alerts == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No strong emerging signal yet.'),
              )
            else
              for (final alert in items.take(3)) ...[
                const Divider(height: 20),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _creatingAlertId == null
                      ? () => _generateAlert(alert)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                                textDirection: contentDirection(alert.title),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${alert.source} · Tap to create a trend video',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6941C6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _creatingAlertId == alert.id
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.movie_creation_outlined),
                      ],
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _weeklyPlan(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: (today.weekday + 1) % 7));
    final planned =
        widget.brand.weeklyPlan['${_selectedDay.weekday - 1}'] ?? [];
    final rahboom =
        Uri.tryParse(widget.brand.website)?.host.replaceFirst('www.', '') ==
        'rahboom.com';
    final daily = (_posts ?? <Post>[])
        .where(
          (p) =>
              p.forDate == DateFormat('yyyy-MM-dd').format(_selectedDay) &&
              p.content['weekly_series'] != null,
        )
        .firstOrNull;
    final rahboomDay = (_selectedDay.weekday + 1) % 7;
    const promoAngles = [
      'choosing Claude Max 5x or 20x by real usage',
      'choosing ChatGPT Plus for a daily work workflow',
      'using Cursor for coding with review and testing',
      'planning a short Google Flow video with fixed references',
      'using Gemini for research and source checking',
      'choosing one AI subscription instead of buying every tool',
      'starting a Rahboom consultation from the customer’s actual task',
    ];
    const newsLenses = [
      'new AI model announcements',
      'important product feature updates',
      'access, pricing or plan changes',
      'new AI video and creator tools',
      'AI coding and GitHub updates',
      'AI safety, privacy or policy changes',
      'the strongest verified AI story of the week',
    ];
    const trendLenses = [
      'a breakout Google search related to AI',
      'a fast-growing YouTube video format',
      'a Persian AI search phrase gaining attention',
      'a product-comparison topic people are searching',
      'a tutorial topic rising today',
      'a practical workflow appearing across sources',
      'the week’s strongest cross-source trend',
    ];
    const educationAngles = [
      'writing a precise prompt with goal, context and output format',
      'checking the original source and date of an AI claim',
      'choosing an AI tool based on the task instead of popularity',
      'protecting private information when using AI tools',
    ];
    final date = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final rahboomSlots = <(String, String, String)>[
      (
        'News',
        'news',
        'NEWS VIDEO for $date — focus on ${newsLenses[rahboomDay]}. Use the newest matching verified story from the Daily radar, include its source URL and publication date in the caption, and never invent a claim.',
      ),
      (
        'Fast trend',
        'trending',
        'TREND VIDEO for $date — focus on ${trendLenses[rahboomDay]}. Use a verified Google or YouTube signal and explain why it matters now without claiming unsupported search volume.',
      ),
      (
        'Promotion',
        'promo',
        'PROMOTIONAL VIDEO for $date — angle: ${promoAngles[rahboomDay]}. Use one real saved Rahboom product, one clear benefit and no unverified price, feature or urgency.',
      ),
      if (rahboomDay.isEven)
        (
          'Educational',
          'educational',
          'EDUCATIONAL VIDEO for $date — teach ${educationAngles[rahboomDay ~/ 2]}. Give one practical takeaway and make no unsupported promise.',
        ),
    ];
    const labels = {
      'educational': 'Educational',
      'sales': 'Sales',
      'promo': 'Promotional',
      'news': 'News',
      'trending': 'Trending',
      'engagement': 'Engagement',
      'video_prompt': 'Custom',
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly plan',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onTab(4),
                  child: const Text('Edit'),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _weekDay(start.add(Duration(days: i)), today),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('EEEE, MMM d', 'en').format(_selectedDay),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (rahboom) ...[
              const SizedBox(height: 8),
              const Text('Video prompts for this day'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slot in rahboomSlots)
                    ActionChip(
                      avatar: const Icon(Icons.movie_outlined, size: 17),
                      label: Text(slot.$1),
                      onPressed: () => widget.onCreate(
                        postType: 'video_prompt',
                        topic: slot.$3,
                        mode: 'video',
                        contentLabel: slot.$2,
                      ),
                    ),
                ],
              ),
            ],
            if (rahboom && daily == null) ...[
              const SizedBox(height: 8),
              const Text(
                'Seven different videos, with complete prompts ready to copy.',
              ),
              FilledButton.icon(
                onPressed: _preparingWeek ? null : _prepareWeek,
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  _preparingWeek ? 'Preparing…' : 'Prepare 7 video prompts',
                ),
              ),
            ],
            if (daily != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(daily.contentLabel),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        daily.title,
                        textDirection: contentDirection(daily.title),
                      ),
                    ),
                  ],
                ),
                subtitle: const Text(
                  '10 seconds · Google Flow · Ready to copy',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(daily),
              ),
            if (!rahboom && planned.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No content planned for this day.'),
              ),
            for (final item in rahboom ? <String>[] : planned)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_outlined),
                title: Text(
                  '${labels[item.split(':').first] ?? item.split(':').first} video',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onCreate(
                  postType: item.split(':').first,
                  mode: 'video',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekDay(DateTime day, DateTime today) {
    final selected = DateUtils.isSameDay(day, _selectedDay);
    final planned =
        (_posts ?? <Post>[]).any(
          (p) =>
              p.forDate == DateFormat('yyyy-MM-dd').format(day) &&
              p.content['weekly_series'] != null,
        ) ||
        (widget.brand.weeklyPlan['${day.weekday - 1}']?.isNotEmpty ?? false);
    return Semantics(
      selected: selected,
      label: DateFormat('EEEE, MMMM d', 'en').format(day),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedDay = day),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? PColors.forest : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: DateUtils.isSameDay(day, today)
                ? Border.all(color: PColors.green)
                : null,
          ),
          child: Column(
            children: [
              Text(
                DateFormat('EE', 'en').format(day).substring(0, 2),
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : PColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : PColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.circle,
                size: 5,
                color: planned
                    ? (selected ? Colors.white : PColors.green)
                    : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

(int, int, int) toJalali(DateTime g) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  var gy = g.year;
  final gy2 = g.month > 2 ? gy + 1 : gy;
  var days =
      355666 +
      365 * gy +
      (gy2 + 3) ~/ 4 -
      (gy2 + 99) ~/ 100 +
      (gy2 + 399) ~/ 400 +
      g.day +
      gdm[g.month - 1];
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
