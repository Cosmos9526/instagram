import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

/// Gallery of every slide template and video style. With [pickPostType] or [pickVideoStyle] it works as a
/// picker and pops the chosen template code / style id ('' = automatic).
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, required this.api, this.pickPostType, this.pickVideoStyle = false});
  final Api api;
  final String? pickPostType;
  final bool pickVideoStyle;

  bool get picking => pickPostType != null || pickVideoStyle;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  Catalog? _catalog;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _filter = widget.pickPostType ?? '';
    widget.api.catalog().then((c) => mounted ? setState(() => _catalog = c) : null).catchError((Object e) {
      if (mounted) showSnack(context, '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _catalog;
    final slides = _SlidesTab(
      api: widget.api,
      catalog: c,
      filter: _filter,
      picking: widget.pickPostType != null,
      onFilter: (f) => setState(() => _filter = f),
    );
    final videos = _VideoTab(catalog: c, picking: widget.pickVideoStyle);
    if (widget.picking) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.pickVideoStyle ? 'انتخاب سبک ویدیو' : 'انتخاب قالب')),
        body: widget.pickVideoStyle ? videos : slides,
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قالب‌ها'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'قالب‌های اسلاید'),
              Tab(text: 'سبک‌های ویدیو'),
            ],
          ),
        ),
        body: TabBarView(children: [slides, videos]),
      ),
    );
  }
}

class _SlidesTab extends StatelessWidget {
  const _SlidesTab({
    required this.api,
    required this.catalog,
    required this.filter,
    required this.picking,
    required this.onFilter,
  });
  final Api api;
  final Catalog? catalog;
  final String filter;
  final bool picking;
  final ValueChanged<String> onFilter;

  @override
  Widget build(BuildContext context) {
    final c = catalog;
    if (c == null) return const Center(child: CircularProgressIndicator());
    final list = filter.isEmpty ? c.templates : c.forType(filter);
    return CustomScrollView(
      slivers: [
        if (!picking)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  for (final (k, v) in [
                    ('', 'همه'),
                    ...postTypes.entries.where((e) => e.key != 'video_prompt').map((e) => (e.key, e.value)),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(label: Text(v), selected: filter == k, onSelected: (_) => onFilter(k)),
                    ),
                ],
              ),
            ),
          ),
        if (picking)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(''),
                icon: const Icon(Icons.shuffle),
                label: const Text('خودکار (هر بار قالب متفاوت)'),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final t = list[i];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: picking && !t.carousel ? () => Navigator.of(context).pop(t.code) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1080 / 1350,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: t.preview == null
                            ? Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)
                            : Image.network(
                                api.mediaUrl(t.preview!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.carousel ? 'بخشی از کاروسل' : t.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VideoTab extends StatelessWidget {
  const _VideoTab({required this.catalog, required this.picking});
  final Catalog? catalog;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final c = catalog;
    if (c == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (picking)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(''),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('بدون سبک مشخص (انتخاب با هوش مصنوعی)'),
          ),
        for (final s in c.videoStyles)
          Card(
            margin: const EdgeInsets.only(top: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: picking ? () => Navigator.of(context).pop(s.id) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.movie_filter_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.name, style: theme.textTheme.titleSmall)),
                        for (final t in s.bestFor.take(2))
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 4),
                            child: Text(postTypes[t] ?? t, style: theme.textTheme.labelSmall),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(s.description),
                    const SizedBox(height: 8),
                    Text(
                      [for (var i = 0; i < s.beats.length; i++) 'کلیپ ${faDigits(i + 1)}: ${s.beats[i]}'].join('\n'),
                      style: theme.textTheme.bodySmall,
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
