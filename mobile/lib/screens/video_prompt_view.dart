import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _secs(num s) => faDigits(s % 1 == 0 ? s.toInt() : s);

/// A video production package: timeline of shots, the opening-frame prompt, one English prompt per shot
/// (in generation order) with its Persian voice-over and on-screen text, music and caption.
class VideoPromptView extends StatelessWidget {
  const VideoPromptView({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final c = post.content;
    final clips = [for (final e in (c['clips'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = clips.fold<num>(0, (n, cl) => n + ((cl['seconds'] as num?) ?? 8));
    final starts = <num>[];
    var t = 0 as num;
    for (final cl in clips) {
      starts.add(t);
      t += (cl['seconds'] as num?) ?? 8;
    }

    return ListView(
      padding: pagePadding(context, maxWidth: 760, top: 8, bottom: 32),
      children: [
        Row(
          children: [
            const TypeBadge('video_prompt', label: 'ویدیو'),
            const SizedBox(width: 8),
            Text(
              '${faDigits(total)} ثانیه · ${faDigits(clips.length)} شات · ۹:۱۶',
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${c['title'] ?? ''}', style: theme.textTheme.titleLarge),
        if ('${c['idea'] ?? ''}'.isNotEmpty) Text('${c['idea']}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        // Timeline: one segment per shot, proportional to its duration.
        if (clips.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                for (final (i, cl) in clips.indexed)
                  Expanded(
                    flex: (((cl['seconds'] as num?) ?? 8) * 10).round(),
                    child: Container(
                      height: 38,
                      margin: EdgeInsetsDirectional.only(end: i == clips.length - 1 ? 0 : 2),
                      color: i.isEven ? scheme.primary : scheme.primary.withValues(alpha: .72),
                      alignment: Alignment.center,
                      child: Text(
                        'شات ${faDigits(i + 1)}',
                        style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('روش ساخت در Google Flow / Veo', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final (i, s) in const [
                  'پرامپت «فریم اول» را در ابزار تصویر بساز.',
                  'شات ۱ را در حالت تصویر به ویدیو، با همان تصویر به‌عنوان فریم شروع بساز.',
                  'آخرین فریم هر شات را ذخیره کن و فریم شروع شات بعدی کن.',
                  'شات‌ها را به ترتیب کنار هم بگذار؛ گویندگی، متن روی تصویر و موسیقی را در تدوین اضافه کن.',
                ].indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${faDigits(i + 1)}. ',
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800),
                        ),
                        Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'مدت هر شات را با محدودیت فعلی ابزار تولید چک کن؛ این فقط زمان‌بندی تدوین است.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if ('${c['keyframe_prompt'] ?? ''}'.isNotEmpty) ...[
          const SectionTitle('فریم اول', subtitle: 'تصویر شروع ویدیو'),
          PromptBlock(text: '${c['keyframe_prompt']}', label: 'Opening frame — image prompt'),
        ],
        for (final (i, clip) in clips.indexed) ...[
          SectionTitle(
            'شات ${faDigits(i + 1)}',
            subtitle: 'از ثانیه‌ی ${_secs(starts[i])} تا ${_secs(starts[i] + ((clip['seconds'] as num?) ?? 8))}',
          ),
          PromptBlock(text: '${clip['full_prompt'] ?? clip['action'] ?? ''}', label: 'Shot ${i + 1} — video prompt'),
          if ('${clip['voiceover'] ?? ''}'.isNotEmpty || '${clip['caption_text'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  if ('${clip['voiceover'] ?? ''}'.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.record_voice_over_outlined),
                      title: const Text('گویندگی'),
                      subtitle: SelectableText('${clip['voiceover']}', style: theme.textTheme.bodyMedium),
                    ),
                  if ('${clip['caption_text'] ?? ''}'.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.subtitles_outlined),
                      title: const Text('متن روی تصویر'),
                      subtitle: SelectableText('${clip['caption_text']}', style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ],
        ],
        if ('${c['music_mood'] ?? ''}'.isNotEmpty) ...[
          const SectionTitle('موسیقی'),
          PromptBlock(text: '${c['music_mood']}', label: 'Music mood'),
        ],
        SectionTitle(
          'کپشن',
          trailing: TextButton.icon(
            onPressed: () => copyText(context, post.captionWithTags, label: 'کپشن و هشتگ‌ها کپی شد'),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('کپی'),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(14), child: SelectableText(post.captionWithTags)),
        ),
      ],
    );
  }
}
