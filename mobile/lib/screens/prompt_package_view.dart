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
    final blocks = (c['blocks'] as List? ?? const []);
    final fullPrompt = '${c['full_prompt'] ?? ''}'.trim().isNotEmpty
        ? '${c['full_prompt']}'
        : blocks
              .where(
                (b) =>
                    '${b['label']}' != 'Reference status' &&
                    '${b['label']}' != 'Production checklist',
              )
              .map((b) => '${b['label']}\n${b['text']}')
              .join('\n\n');
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
                  label.endsWith('— prompt') ||
                      label == 'Visual style' ||
                      label == 'Full video prompt' ||
                      label == 'Reference status' ||
                      label == 'Opening frame — prompt'
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
        Text(
          post.isVideo
              ? 'Attach your character reference and logo in Google Flow, then copy the complete brief below.'
              : 'Copy the complete brief into your production tool.',
        ),
        const SizedBox(height: 16),
        Text(
          '${c['title'] ?? ''}',
          textDirection: contentDirection('${c['title'] ?? ''}'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => copyText(context, fullPrompt),
          icon: const Icon(Icons.copy),
          label: const Text('Copy full prompt'),
        ),
        const SizedBox(height: 12),
        copyCard(
          post.isVideo ? 'Full video prompt' : 'Visual style',
          fullPrompt,
        ),
        if ('${c['cover_prompt'] ?? ''}'.trim().isNotEmpty)
          copyCard('Cover — prompt', '${c['cover_prompt']}'),
        copyCard('Caption and hashtags', post.captionWithTags),
      ],
    );
  }
}
