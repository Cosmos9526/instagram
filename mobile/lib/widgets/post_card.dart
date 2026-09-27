import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Visual tile for one piece of content: 4:5 preview, objective badge, status and title.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.api, required this.onTap});
  final Post post;
  final Api api;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final format = post.isVideo
        ? 'ویدیو ${faDigits(post.content['total_seconds'] ?? post.content['target_seconds'] ?? '')} ثانیه'
        : post.mode == 'carousel'
        ? 'کاروسل ${faDigits(post.slides.length)} اسلاید'
        : 'تک‌اسلاید';

    Widget preview;
    if (post.slides.isNotEmpty) {
      preview = Image.network(
        '${api.thumbUrl(post.slides.first, 480)}&s=${post.status}',
        fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      final (bg, fg) = PColors.objective(post.isVideo ? 'video_prompt' : post.postType, dark);
      preview = Container(
        color: bg,
        alignment: Alignment.center,
        child: post.isBusy
            ? SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
            : Icon(
                post.status == 'failed'
                    ? Icons.error_outline
                    : post.isVideo
                    ? Icons.movie_creation_outlined
                    : Icons.image_outlined,
                size: 34,
                color: fg,
              ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.surfaceContainerHigh, child: preview),
                  if (post.mode == 'carousel' && post.slides.length > 1)
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.collections_outlined, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TypeBadge(post.isVideo ? 'video_prompt' : post.postType, label: post.isVideo ? 'ویدیو' : null),
                      const Spacer(),
                      StatusChip(post.status, dense: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    post.isBusy ? 'در حال ساخت…' : post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.55),
                  ),
                  Text(
                    format,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of [PostCard]s: 2 columns on phones, up to 5 on wide screens.
class PostGrid extends StatelessWidget {
  const PostGrid({super.key, required this.posts, required this.api, required this.onOpen});
  final List<Post> posts;
  final Api api;
  final ValueChanged<Post> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = (c.maxWidth / 190).floor().clamp(2, 5);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final p in posts)
            SizedBox(
              width: w,
              child: PostCard(post: p, api: api, onTap: p.isBusy ? null : () => onOpen(p)),
            ),
        ],
      );
    },
  );
}
