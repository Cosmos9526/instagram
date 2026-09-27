import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'edit_screen.dart';
import 'video_prompt_view.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.api, required this.postId});
  final Api api;
  final String postId;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Post? _post;
  Timer? _poll;
  bool _busy = false;
  int _page = 0;
  // Bumped after a re-render so cached images are refetched.
  int _version = 0;

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
      final p = await widget.api.post(widget.postId);
      if (!mounted) return;
      final wasBusy = _post?.isBusy ?? false;
      setState(() {
        _post = p;
        if (wasBusy && !p.isBusy) _version++;
      });
      _poll?.cancel();
      if (p.isBusy) _poll = Timer(const Duration(seconds: 3), _load);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _act(Future<Post> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      final p = await call();
      if (!mounted) return;
      setState(() => _post = p);
      showSnack(context, done);
      if (p.isBusy) _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(Post p) async {
    setState(() => _busy = true);
    try {
      // XFile.fromData works on Android, iOS and in the browser (Web Share API).
      final files = <XFile>[
        for (var i = 0; i < p.slides.length; i++)
          XFile.fromData(
            (await http.get(Uri.parse(widget.api.mediaUrl(p.slides[i])))).bodyBytes,
            name: 'postyar_${i + 1}.png',
            mimeType: 'image/png',
          ),
      ];
      if (!mounted) return;
      await copyText(context, p.captionWithTags, label: 'کپشن کپی شد؛ بعد از انتخاب اینستاگرام Paste کن');
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (_) {
      if (mounted) showSnack(context, 'اشتراک‌گذاری ناموفق بود');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? '' : postTypes[p.postType] ?? ''),
        actions: [if (p != null) Padding(padding: const EdgeInsets.all(12), child: StatusChip(p.status))],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : p.isBusy
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('در حال ساخت…')],
              ),
            )
          : p.status == 'failed'
          ? _failed(p)
          : p.isVideo
          ? VideoPromptView(post: p)
          : _slides(p),
      bottomNavigationBar: p == null || p.isBusy ? null : _actions(p),
    );
  }

  Widget _failed(Post p) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('ساخت این پست ناموفق بود.'),
          const SizedBox(height: 8),
          Text(
            p.error,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _slides(Post p) {
    // Always the whole slide at its real 4:5 ratio, never taller than ~62% of the screen.
    // (MediaQuery width is the browser window, not the phone-width column, so size by aspect ratio.)
    final maxWidth = MediaQuery.sizeOf(context).height * 0.62 * 1080 / 1350;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (p.content['source'] == 'offline') _OfflineNote(),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: AspectRatio(
              aspectRatio: 1080 / 1350,
              child: PageView.builder(
                itemCount: p.slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    '${widget.api.thumbUrl(p.slides[i], 1080)}&v=$_version',
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (p.slides.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < p.slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: i == _page ? 1 : .3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
        SectionTitle(
          'کپشن',
          trailing: IconButton(
            tooltip: 'کپی کپشن و هشتگ‌ها',
            icon: const Icon(Icons.copy),
            onPressed: () => copyText(context, p.captionWithTags),
          ),
        ),
        SelectableText(p.caption),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final h in p.hashtags) Chip(label: Text('#$h'), visualDensity: VisualDensity.compact)],
        ),
      ],
    );
  }

  Widget _actions(Post p) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          if (!p.isVideo && p.status != 'failed') ...[
            IconButton.filledTonal(
              tooltip: 'ویرایش متن',
              onPressed: _busy
                  ? null
                  : () async {
                      final content = await Navigator.of(
                        context,
                      ).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => EditScreen(post: p)));
                      if (content != null) {
                        await _act(() => widget.api.editPost(p.id, content), 'در حال رندر دوباره…');
                      }
                    },
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'اشتراک در اینستاگرام',
              onPressed: _busy ? null : () => _share(p),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
          IconButton.filledTonal(
            tooltip: 'ساخت دوباره',
            onPressed: _busy ? null : () => _act(() => widget.api.review(p.id, 'regenerate'), 'دوباره ساخته می‌شود'),
            icon: const Icon(Icons.refresh),
          ),
          const Spacer(),
          if (p.status != 'failed') ...[
            TextButton(
              onPressed: _busy || p.status == 'rejected'
                  ? null
                  : () => _act(() => widget.api.review(p.id, 'reject'), 'رد شد'),
              child: const Text('رد'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _busy || p.status == 'approved'
                  ? null
                  : () => _act(() => widget.api.review(p.id, 'approve'), 'تأیید شد'),
              child: const Text('تأیید'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _OfflineNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
      child: const Text(
        'این پست بدون مدل هوش مصنوعی و از روی قالب آماده ساخته شد (مدل در دسترس نبود). '
        'متن را ویرایش کنید یا وقتی مدل فعال شد «ساخت دوباره» را بزنید.',
      ),
    );
  }
}
