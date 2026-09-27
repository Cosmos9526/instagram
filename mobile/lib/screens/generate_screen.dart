import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'templates_screen.dart';

/// Guided create: objective → format → style → topic → one button. Objective and format are chosen
/// separately; for a video the objective is passed to the model with the topic.
class GenerateScreen extends StatefulWidget {
  const GenerateScreen({super.key, required this.api, required this.brand, required this.onCreated});
  final Api api;
  final Brand brand;
  final VoidCallback onCreated;

  @override
  State<GenerateScreen> createState() => GenerateScreenState();
}

const _objectives = [
  ('educational', Icons.school_outlined, 'آموزشی', 'نکته، راهنما، پاسخ به سؤال'),
  ('news', Icons.bolt_outlined, 'خبری', 'خبر یا ترند روز'),
  ('promo', Icons.campaign_outlined, 'تبلیغاتی', 'معرفی برند و محصول'),
  ('sales', Icons.sell_outlined, 'فروش محصول', 'پیشنهاد، تخفیف، دعوت به خرید'),
];

const _formats = [
  ('single', Icons.crop_portrait_rounded, 'تک‌اسلاید'),
  ('carousel', Icons.view_carousel_outlined, 'کاروسل'),
  ('video', Icons.movie_creation_outlined, 'ویدیو'),
];

class GenerateScreenState extends State<GenerateScreen> {
  String _objective = 'educational';
  String _format = 'single';
  String _template = '';
  String _videoStyle = '';
  int _nBody = 4;
  int _seconds = 16;
  final _topic = TextEditingController();
  bool _busy = false;
  Catalog? _catalog;

  bool get _isVideo => _format == 'video';

  @override
  void initState() {
    super.initState();
    widget.api.catalog().then((c) => mounted ? setState(() => _catalog = c) : null).catchError((_) => null);
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  /// Called from home, market and competitors: "make content from this".
  void prefill({required String postType, String topic = '', String mode = 'single', String videoStyle = ''}) {
    setState(() {
      if (postType == 'video_prompt') {
        _format = 'video';
      } else {
        _objective = postType;
        _format = mode == 'carousel' ? 'carousel' : (mode == 'video' ? 'video' : 'single');
      }
      _template = '';
      _videoStyle = videoStyle;
      _topic.text = topic;
    });
  }

  Future<void> _pickTemplate() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(api: widget.api, pickPostType: _objective),
      ),
    );
    if (code != null) setState(() => _template = code);
  }

  Future<void> _pickStyle() async {
    final id = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => TemplatesScreen(api: widget.api, pickVideoStyle: true)));
    if (id != null) setState(() => _videoStyle = id);
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final topic = _topic.text.trim();
      final objectiveLabel = _objectives.firstWhere((o) => o.$1 == _objective).$3;
      final req = GenerateRequest(
        postType: _isVideo ? 'video_prompt' : _objective,
        mode: _isVideo ? 'video' : _format,
        topicHint: _isVideo ? 'هدف ویدیو: $objectiveLabel.${topic.isEmpty ? '' : ' $topic'}' : topic,
        template: _template,
        videoStyle: _videoStyle,
        nBody: _nBody,
        targetSeconds: _seconds,
      );
      await widget.api.generate(widget.brand.id!, req);
      _topic.clear();
      if (!mounted) return;
      showSnack(context, 'در حال ساخت… چند ثانیه‌ی دیگر در «امروز» آماده است');
      widget.onCreated();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = _catalog?.templates.where((t) => t.code == _template).firstOrNull;
    final style = _catalog?.style(_videoStyle);
    final topicHint = switch ((_objective, _isVideo)) {
      (_, true) => 'ایده یا سناریو، مثلاً «کاربری که بعد از ۱۰ دقیقه جواب درست از ChatGPT می‌گیرد…» (اختیاری)',
      ('news', _) => 'متن یا لینک خبر را اینجا بگذار (اختیاری؛ بدون آن از ترندهای بازار استفاده می‌شود)',
      ('sales', _) => 'پیشنهاد یا تخفیف واقعی، مثلاً «۱۰٪ تخفیف ChatGPT Plus تا جمعه» (اختیاری)',
      _ => 'موضوع، سؤال مشتری یا ایده (اختیاری)',
    };

    return ListView(
      padding: pagePadding(context, maxWidth: 720),
      children: [
        Text('ساخت محتوا', style: theme.textTheme.headlineSmall),
        Text(
          'چهار انتخاب ساده؛ بقیه را هوش مصنوعی با اطلاعات برند و رقبا کامل می‌کند.',
          style: theme.textTheme.bodySmall,
        ),
        const _Step(n: 1, title: 'هدف این محتوا چیست؟'),
        ResponsiveGrid(
          minTile: 160,
          spacing: 8,
          children: [
            for (final o in _objectives)
              _ChoiceCard(
                icon: o.$2,
                title: o.$3,
                body: o.$4,
                selected: _objective == o.$1,
                color: PColors.objective(o.$1, theme.brightness == Brightness.dark),
                onTap: () => setState(() {
                  _objective = o.$1;
                  _template = '';
                }),
              ),
          ],
        ),
        const _Step(n: 2, title: 'در چه قالبی؟'),
        Row(
          children: [
            for (final f in _formats) ...[
              if (f != _formats.first) const SizedBox(width: 8),
              Expanded(
                child: _ChoiceCard(
                  icon: f.$2,
                  title: f.$3,
                  selected: _format == f.$1,
                  compact: true,
                  onTap: () => setState(() => _format = f.$1),
                ),
              ),
            ],
          ],
        ),
        _Step(n: 3, title: _isVideo ? 'سبک و مدت ویدیو' : (_format == 'carousel' ? 'تعداد اسلاید' : 'ظاهر اسلاید')),
        if (_format == 'single')
          _PickerTile(
            icon: Icons.dashboard_customize_outlined,
            title: template?.name ?? 'انتخاب خودکار قالب',
            subtitle: _template.isEmpty ? 'هر بار قالبی متفاوت و مناسب هدف' : 'برای عوض کردن بزن',
            preview: template?.preview == null ? null : widget.api.mediaUrl(template!.preview!),
            onTap: _pickTemplate,
          ),
        if (_format == 'carousel')
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${faDigits(_nBody + 2)} اسلاید: کاور + ${faDigits(_nBody)} اسلاید محتوا + دعوت به اقدام',
                    style: theme.textTheme.titleSmall,
                  ),
                  Slider(
                    value: _nBody.toDouble(),
                    min: 2,
                    max: 8,
                    divisions: 6,
                    label: faDigits(_nBody + 2),
                    onChanged: (v) => setState(() => _nBody = v.round()),
                  ),
                ],
              ),
            ),
          ),
        if (_isVideo) ...[
          _PickerTile(
            icon: Icons.movie_filter_outlined,
            title: style?.name ?? 'سبک را هوش مصنوعی انتخاب کند',
            subtitle: style?.description ?? 'POV، قبل و بعد، آموزش قدم‌به‌قدم، آنباکسینگ و …',
            onTap: _pickStyle,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('مدت:', style: theme.textTheme.titleSmall),
              for (final s in const [10, 16, 24, 32, 40])
                ChoiceChip(
                  label: Text('${faDigits(s)} ثانیه'),
                  selected: _seconds == s,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _seconds = s),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '≈ ${faDigits((_seconds / 8).round().clamp(1, 4))} شات پیوسته؛ هر شات یک پرامپت انگلیسی جدا برای Google Flow / Veo',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const _Step(n: 4, title: 'موضوع یا منبع'),
        TextField(
          controller: _topic,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: topicHint),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(
            _isVideo
                ? 'ساخت سناریو و پرامپت ویدیو'
                : 'ساخت ${_format == 'carousel' ? 'کاروسل' : 'پست'} ${_objectives.firstWhere((o) => o.$1 == _objective).$3}',
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title});
  final int n;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Text(
              faDigits(n),
              style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w800, height: 1.3),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.body,
    this.color,
    this.compact = false,
  });
  final IconData icon;
  final String title;
  final String? body;
  final bool selected, compact;
  final (Color, Color)? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = color ?? (scheme.primaryContainer, scheme.onPrimaryContainer);
    return Material(
      color: selected ? bg : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.all(compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? fg : scheme.outlineVariant, width: selected ? 1.6 : 1),
          ),
          child: compact
              ? Column(
                  children: [
                    Icon(icon, color: selected ? fg : scheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w700, color: selected ? fg : scheme.onSurface),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(icon, color: selected ? fg : scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(fontWeight: FontWeight.w800, color: selected ? fg : scheme.onSurface),
                          ),
                          if (body != null)
                            Text(
                              body!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (selected) Icon(Icons.check_circle, size: 20, color: fg),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.preview,
  });
  final IconData icon;
  final String title, subtitle;
  final String? preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 55,
                  child: preview == null
                      ? ColoredBox(
                          color: scheme.primaryContainer,
                          child: Icon(icon, color: scheme.onPrimaryContainer),
                        )
                      : Image.network(
                          preview!,
                          fit: BoxFit.cover,
                          cacheWidth: 132,
                          errorBuilder: (_, _, _) => Icon(icon),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                'تغییر',
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
