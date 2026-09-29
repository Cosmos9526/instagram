import 'dart:async';
import 'package:flutter/material.dart';
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
