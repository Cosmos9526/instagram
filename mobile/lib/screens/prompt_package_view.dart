import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PromptPackageView extends StatelessWidget {
  const PromptPackageView({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final c = post.content;
    Widget copyCard(String label, String text) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => copyText(context, text),
                ),
              ],
            ),
            SelectableText(
              text,
              textDirection:
                  label.endsWith('— prompt') || label == 'Visual style'
                  ? TextDirection.ltr
                  : contentDirection(text),
              textAlign: TextAlign.start,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.7),
            ),
          ],
        ),
      ),
    );
    return ListView(
      padding: pagePadding(context, maxWidth: 760, top: 12, bottom: 32),
      children: [
        Text(
          'Prompt package',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          post.isVideo
              ? '10 seconds · 8-second scene + 2-second end card · 9:16'
              : 'Image prompts · 4:5',
        ),
        const Text(
          'Copy these prompts into your production tool. No media is generated here.',
        ),
        const SizedBox(height: 16),
        copyCard('Title', '${c['title'] ?? ''}'),
        for (final block in (c['blocks'] as List? ?? const []))
          copyCard('${block['label']}', '${block['text']}'),
        copyCard('Caption and hashtags', post.captionWithTags),
      ],
    );
  }
}
