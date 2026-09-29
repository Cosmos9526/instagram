import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';
import 'post_screen.dart';

/// Content library: every post of the project as a visual grid, filterable by status.
/// Polls while posts are being built.
class PostsScreen extends StatefulWidget {
  const PostsScreen({
    super.key,
    required this.api,
    required this.brand,
    this.standalone = false,
  });
  final Api api;
  final Brand brand;

  /// Opened as its own page (with an app bar) rather than as a tab.
  final bool standalone;

  @override
  State<PostsScreen> createState() => PostsScreenState();
}

class PostsScreenState extends State<PostsScreen> {
  List<Post>? _posts;
  String? _error;
  Timer? _poll;
  String _filter = 'all';

  static const _filters = {
    'all': 'View all',
    'ready': 'Needs review',
    'approved': 'Approved',
    'failed': 'Failed',
  };

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

  Widget _body() {
    final posts = _posts;
    if (posts == null) {
      return Center(
        child: _error != null
            ? Text(_error!)
            : const CircularProgressIndicator(),
      );
    }
    final shown = _filter == 'all'
        ? posts
        : posts
              .where(
                (p) =>
                    p.status == _filter ||
                    (_filter == 'failed' && p.status == 'rejected'),
              )
              .toList();
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: pagePadding(
          context,
          maxWidth: 1100,
          bottom: widget.standalone ? 32 : 110,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${e.value} ${uiDigits(e.key == 'all' ? posts.length : posts.where((p) => p.status == e.key).length)}',
                      ),
                      selected: _filter == e.key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = e.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            const EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No content here yet',
              body:
                  'Create your first post or set a weekly plan to prepare content each morning.',
            )
          else
            PostGrid(posts: shown, api: widget.api, onOpen: _open),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.standalone
      ? Scaffold(
          appBar: AppBar(title: const Text('Content library')),
          body: _body(),
        )
      : _body();
}
