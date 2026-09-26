import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'post_screen.dart';

/// Posts list: today's batch first, then everything else. Polls while posts are being built.
class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key, required this.api, required this.brand});
  final Api api;
  final Brand brand;

  @override
  State<PostsScreen> createState() => PostsScreenState();
}

class PostsScreenState extends State<PostsScreen> {
  List<Post>? _posts;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(PostsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand.id != widget.brand.id) {
      _posts = null;
      refresh();
    }
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

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    if (posts == null) {
      return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todays = posts.where((p) => p.forDate == today).toList();
    final older = posts.where((p) => p.forDate != today).toList();

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SectionTitle('امروز'),
          if (todays.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('هنوز پستی برای امروز ساخته نشده. از تب «ساخت» یکی بساز، '
                  'یا صبر کن تا برنامه‌ی روزانه اجرا شود.'),
            ),
          for (final p in todays) _PostTile(post: p, api: widget.api, onChanged: refresh),
          if (older.isNotEmpty) const SectionTitle('قبلی‌ها'),
          for (final p in older) _PostTile(post: p, api: widget.api, onChanged: refresh),
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.api, required this.onChanged});
  final Post post;
  final Api api;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final thumb = post.slides.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(api.mediaUrl(post.slides.first), width: 56, height: 70, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 70)),
          )
        : Container(
            width: 56,
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(post.isVideo ? Icons.movie_creation_outlined : Icons.image_outlined),
          );
    final kind = [
      postTypes[post.postType] ?? post.postType,
      if (post.mode == 'carousel') 'کاروسل ${faDigits(post.slides.length)} اسلایدی',
    ].join('، ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: post.isBusy
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PostScreen(api: api, postId: post.id)),
                );
                onChanged();
              },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            thumb,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kind, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(post.isBusy ? '...' : post.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            StatusChip(post.status),
          ]),
        ),
      ),
    );
  }
}
