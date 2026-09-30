import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/delete_post.dart';
import 'post_screen.dart';
import 'posts_screen.dart';

typedef CreateCallback =
    void Function({
      required String postType,
      String topic,
      String mode,
      String videoStyle,
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
  String? _error;
  Timer? _poll;
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
      final posts = await widget.api.posts(widget.brand.id!);
      if (!mounted) return;
      setState(() {
        _posts = posts;
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

  Future<void> _open(Post p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostScreen(api: widget.api, postId: p.id),
      ),
    );
    refresh();
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
        if (_error != null) Text(_error!),
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
              title: Text(
                p.title,
                textDirection: contentDirection(p.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                p.isBusy
                    ? 'Creating…'
                    : p.status == 'failed'
                    ? 'Needs retry'
                    : p.status == 'approved'
                    ? 'Approved'
                    : 'Ready to review',
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

  Widget _weeklyPlan(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = today.subtract(Duration(days: (today.weekday + 1) % 7));
    final planned =
        widget.brand.weeklyPlan['${_selectedDay.weekday - 1}'] ?? [];
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
            if (planned.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No content planned for this day.'),
              ),
            for (final item in planned)
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
        widget.brand.weeklyPlan['${day.weekday - 1}']?.isNotEmpty ?? false;
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
