import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/common.dart';

/// Shows a video prompt package: one copy button per clip, in the order they must be generated.
class VideoPromptView extends StatelessWidget {
  const VideoPromptView({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final c = post.content;
    final clips = [
      for (final e in (c['clips'] as List? ?? const []))
        Map<String, dynamic>.from(e as Map),
    ];
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('${c['title'] ?? ''}', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text('${c['idea'] ?? ''}'),
        const SizedBox(height: 6),
        Text(
          '${faDigits(c['target_seconds'] ?? c['total_seconds'] ?? '')} ثانیه، ${faDigits(clips.length)} کلیپ',
          style: theme.textTheme.labelLarge,
        ),
        Card(
          color: theme.colorScheme.secondaryContainer,
          margin: const EdgeInsets.symmetric(vertical: 16),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'روش ساخت:\n'
              '۱. «پرامپت فریم اول» را در مدل تصویر بساز.\n'
              '۲. کلیپ ۱ را در حالت «تصویر به ویدیو» با همان عکس به‌عنوان فریم شروع بساز.\n'
              '۳. آخرین فریم هر کلیپ را ذخیره کن و تصویر شروع کلیپ بعدی کن.\n'
              '۴. کلیپ‌ها را به ترتیب کنار هم بگذار، موسیقی و زیرنویس اضافه کن.',
            ),
          ),
        ),
        _PromptCard(
          title: 'پرامپت فریم اول (تصویر)',
          prompt: '${c['keyframe_prompt'] ?? ''}',
        ),
        for (final clip in clips)
          _PromptCard(
            title:
                'کلیپ ${faDigits(clip['n'] ?? '')} — ${faDigits(clip['seconds'] ?? 8)} ثانیه',
            prompt: '${clip['full_prompt'] ?? ''}',
            footer: [
              if ('${clip['voiceover'] ?? ''}'.isNotEmpty)
                'گوینده: ${clip['voiceover']}',
              if ('${clip['caption_text'] ?? ''}'.isNotEmpty)
                'زیرنویس: ${clip['caption_text']}',
            ],
          ),
        if ('${c['music_mood'] ?? ''}'.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('حال‌وهوای موسیقی'),
            subtitle: Text(
              '${c['music_mood']}',
              textDirection: TextDirection.ltr,
            ),
          ),
        SectionTitle(
          'کپشن',
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => copyText(context, post.captionWithTags),
          ),
        ),
        SelectableText(post.captionWithTags),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.title,
    required this.prompt,
    this.footer = const [],
  });
  final String title, prompt;
  final List<String> footer;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'کپی پرامپت',
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    copyText(context, prompt, label: 'پرامپت کپی شد'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              prompt,
              textDirection: TextDirection.ltr,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final f in footer)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(f)),
        ],
      ),
    ),
  );
}
