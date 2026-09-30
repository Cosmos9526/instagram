import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'edit_screen.dart';
import 'video_prompt_view.dart';
import 'prompt_package_view.dart';
import '../widgets/delete_post.dart';

/// One piece of content as a production package: preview, texts, caption, English prompts, review actions.
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
  final _pager = PageController();
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
    _pager.dispose();
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
            (await http.get(
              Uri.parse(widget.api.mediaUrl(p.slides[i])),
            )).bodyBytes,
            name: 'slide_${i + 1}.png',
            mimeType: 'image/png',
          ),
      ];
      if (!mounted) return;
      await copyText(
        context,
        p.captionWithTags,
        label: 'Caption copied. After opening Instagram, Paste it',
      );
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (_) {
      if (mounted) showSnack(context, 'Could not share');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Post p) async {
    final content = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => EditScreen(post: p)),
    );
    if (content != null) {
      await _act(() => widget.api.editPost(p.id, content), 'Rendering again…');
    }
  }

  void _goTo(int i) => _pager.animateToPage(
    i,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final p = _post;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p == null
              ? ''
              : (p.isVideo ? 'Video production brief' : 'Publishing package'),
        ),
        actions: [
          if (p != null && !p.isBusy)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final removed = await deletePost(context, widget.api, p);
                if (!context.mounted || !removed) return;
                Navigator.pop(context);
              },
            ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: StatusChip(p.status),
            ),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : p.isBusy
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Creating…'),
                ],
              ),
            )
          : p.status == 'failed'
          ? _failed(p)
          : p.content['output_kind'] == 'prompt_package'
          ? PromptPackageView(post: p)
          : p.isVideo
          ? VideoPromptView(post: p)
          : _slides(p),
      bottomNavigationBar: p == null || p.isBusy ? null : _actions(p),
    );
  }

  Widget _failed(Post p) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Content generation failed',
          body: p.error.isEmpty ? 'Please try again.' : p.error,
          action: FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _act(
                    () => widget.api.review(p.id, 'regenerate'),
                    'Regeneration queued',
                  ),
            icon: const Icon(Icons.refresh),
            label: const Text('Regenerate'),
          ),
        ),
      ),
    ),
  );

  Widget _preview(Post p, double maxWidth) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: AspectRatio(
            aspectRatio: 1080 / 1350,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pager,
                  itemCount: p.slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: Image.network(
                        '${widget.api.thumbUrl(p.slides[i], 1080)}&v=$_version',
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ),
                ),
                if (p.slides.length > 1) ...[
                  if (_page > 0)
                    PositionedDirectional(
                      start: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_left,
                          onTap: () => _goTo(_page - 1),
                        ),
                      ),
                    ),
                  if (_page < p.slides.length - 1)
                    PositionedDirectional(
                      end: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _ArrowButton(
                          icon: Icons.chevron_right,
                          onTap: () => _goTo(_page + 1),
                        ),
                      ),
                    ),
                ],
              ],
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
                  GestureDetector(
                    onTap: () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(
                          alpha: i == _page ? 1 : .3,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Persian text of each slide, in order (cover, body slides, call to action), or the single slide's slots.
  List<(String, String)> _slideTexts(Post p) {
    final c = p.content;
    final out = <(String, String)>[];
    String join(Map? m) => [
      for (final k in const [
        'kicker',
        'headline',
        'question',
        'myth',
        'fact',
        'quote',
        'stat',
        'body',
        'answer',
        'cta',
      ])
        if ('${m?[k] ?? ''}'.trim().isNotEmpty) '${m![k]}',
    ].join('\n');
    if (c['cover'] is Map) out.add(('Cover', join(c['cover'] as Map)));
    for (final (i, b) in ((c['body'] as List?) ?? const []).indexed) {
      if (b is Map) out.add(('Slide ${uiDigits(i + 2)}', join(b)));
    }
    if (c['cta'] is Map) out.add(('Call to action', join(c['cta'] as Map)));
    if (out.isEmpty && c['slots'] is Map) {
      out.add(('Slide text', join(c['slots'] as Map)));
    }
    return [
      for (final t in out)
        if (t.$2.trim().isNotEmpty) t,
    ];
  }

  Widget _details(Post p) {
    final theme = Theme.of(context);
    final texts = _slideTexts(p);
    final imagePrompt = '${p.content['image_prompt'] ?? ''}'.trim();
    final format = p.mode == 'carousel'
        ? 'Carousel ${uiDigits(p.slides.length)} Slide'
        : 'Single slide';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TypeBadge(p.postType),
            const SizedBox(width: 8),
            Text(
              format,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          p.title,
          textDirection: contentDirection(p.title),
          style: theme.textTheme.titleLarge,
        ),
        if (p.content['source'] == 'offline') ...[
          const SizedBox(height: 12),
          _OfflineNote(),
        ],
        SectionTitle(
          'Caption',
          trailing: TextButton.icon(
            onPressed: () => copyText(
              context,
              p.captionWithTags,
              label: 'Caption and hashtags copied',
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  p.caption,
                  textDirection: contentDirection(p.caption),
                ),
                if (p.hashtags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final h in p.hashtags)
                        Text(
                          '#${h.replaceAll(' ', '_')}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (texts.isNotEmpty) ...[
          SectionTitle(
            'Slide text',
            trailing: TextButton.icon(
              onPressed: () => _edit(p),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, t) in texts.indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(t.$1, style: theme.textTheme.labelMedium),
                    subtitle: Text(t.$2, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (imagePrompt.isNotEmpty) ...[
          const SectionTitle(
            'Background image prompt',
            subtitle:
                'Generate a background in another tool. Add text separately',
          ),
          PromptBlock(text: imagePrompt, label: 'Image prompt'),
        ],
      ],
    );
  }

  Widget _slides(Post p) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      final h = MediaQuery.sizeOf(context).height;
      return SingleChildScrollView(
        padding: pagePadding(context, maxWidth: 1100, top: 16, bottom: 32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 440, child: _preview(p, (h - 220) * 1080 / 1350)),
            const SizedBox(width: 32),
            Expanded(child: _details(p)),
          ],
        ),
      );
    }
    final maxWidth = MediaQuery.sizeOf(context).height * 0.6 * 1080 / 1350;
    return ListView(
      padding: pagePadding(context, maxWidth: 640, top: 8, bottom: 24),
      children: [
        Center(child: _preview(p, maxWidth)),
        const SizedBox(height: 16),
        _details(p),
      ],
    );
  }

  Widget _actions(Post p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  if (!p.isVideo &&
                      p.status != 'failed' &&
                      p.content['output_kind'] != 'prompt_package') ...[
                    IconButton.filledTonal(
                      tooltip: 'Edit text',
                      onPressed: _busy ? null : () => _edit(p),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Download or share images',
                      onPressed: _busy ? null : () => _share(p),
                      icon: const Icon(Icons.ios_share),
                    ),
                  ],
                  IconButton.filledTonal(
                    tooltip: 'Regenerate',
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => widget.api.review(p.id, 'regenerate'),
                            'Regeneration queued',
                          ),
                    icon: const Icon(Icons.refresh),
                  ),
                  const Spacer(),
                  if (p.status != 'failed') ...[
                    TextButton(
                      onPressed: _busy || p.status == 'rejected'
                          ? null
                          : () => _act(
                              () => widget.api.review(p.id, 'reject'),
                              'Rejected',
                            ),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: _busy || p.status == 'approved'
                          ? null
                          : () => _act(
                              () => widget.api.review(p.id, 'approve'),
                              'Approved',
                            ),
                      icon: const Icon(Icons.check),
                      label: Text(
                        p.status == 'approved' ? 'Approved' : 'Approve',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .45),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: Colors.white),
      ),
    ),
  );
}

class _OfflineNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = PColors.objective(
      'promo',
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Created from a fallback template (AI was unavailable). '
        'Edit the text or regenerate when the model is available.',
        style: TextStyle(color: fg),
      ),
    );
  }
}
