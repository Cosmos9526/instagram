import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, required this.api, required this.brand, required this.onCreated});
  final Api api;
  final Brand brand;
  final VoidCallback onCreated;

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _req = GenerateRequest(postType: 'educational');
  final _topic = TextEditingController();
  bool _busy = false;

  bool get _isVideo => _req.postType == 'video_prompt';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      _req.topicHint = _topic.text.trim();
      await widget.api.generate(widget.brand.id!, _req);
      _topic.clear();
      if (!mounted) return;
      showSnack(context, 'در حال ساخت… نتیجه در تب پست‌ها می‌آید');
      widget.onCreated();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topicHint = switch (_req.postType) {
      'news' => 'خبر یا ترندی که می‌خواهی پوشش بدهی (اختیاری)',
      'video_prompt' => 'ایده‌ی ویدیو، مثلاً «مشتری صبح زود وارد کافه می‌شود…» (اختیاری)',
      'sales' => 'پیشنهاد یا تخفیف واقعی‌ات (اختیاری)',
      _ => 'موضوع یا ترند (اختیاری)',
    };

    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      const SectionTitle('نوع پست'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in postTypes.entries)
          ChoiceChip(
            label: Text(e.value),
            selected: _req.postType == e.key,
            onSelected: (_) => setState(() => _req.postType = e.key),
          ),
      ]),
      if (!_isVideo) ...[
        const SectionTitle('قالب'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'single', label: Text('تک‌اسلاید'), icon: Icon(Icons.crop_portrait)),
            ButtonSegment(value: 'carousel', label: Text('کاروسل'), icon: Icon(Icons.view_carousel_outlined)),
          ],
          selected: {_req.mode},
          onSelectionChanged: (s) => setState(() => _req.mode = s.first),
        ),
        if (_req.mode == 'carousel') ...[
          const SizedBox(height: 16),
          Text('تعداد اسلاید: ${faDigits(_req.nBody + 2)} (کاور + ${faDigits(_req.nBody)} اسلاید + دعوت به اقدام)'),
          Slider(
            value: _req.nBody.toDouble(),
            min: 2,
            max: 8,
            divisions: 6,
            label: faDigits(_req.nBody + 2),
            onChanged: (v) => setState(() => _req.nBody = v.round()),
          ),
        ],
      ] else ...[
        const SectionTitle('مدت ویدیو'),
        Text('${faDigits(_req.targetSeconds)} ثانیه ≈ ${faDigits((_req.targetSeconds / 8).round().clamp(1, 4))} کلیپ پیوسته'),
        Slider(
          value: _req.targetSeconds.toDouble(),
          min: 10,
          max: 40,
          divisions: 6,
          label: faDigits(_req.targetSeconds),
          onChanged: (v) => setState(() => _req.targetSeconds = v.round()),
        ),
      ],
      const SectionTitle('موضوع'),
      TextField(controller: _topic, minLines: 2, maxLines: 5, decoration: InputDecoration(hintText: topicHint)),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _busy ? null : _submit,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.auto_awesome),
        label: Text(_isVideo ? 'ساخت پرامپت ویدیو' : 'ساخت پست'),
      ),
    ]);
  }
}
