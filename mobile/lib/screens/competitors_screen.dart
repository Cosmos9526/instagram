import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'research_screen.dart' show UseIdea;

const _productLabels = <String, String>{
  'chatgpt_plus': 'ChatGPT Plus',
  'chatgpt_pro': 'ChatGPT Pro',
  'chatgpt_team': 'ChatGPT Team',
  'chatgpt': 'ChatGPT',
  'gemini': 'Gemini',
  'claude': 'Claude',
  'midjourney': 'Midjourney',
  'cursor': 'Cursor',
  'perplexity': 'Perplexity',
  'grok': 'Grok',
  'copilot': 'Copilot',
  'canva': 'Canva',
  'capcut': 'CapCut',
  'spotify': 'Spotify',
  'youtube_premium': 'YouTube Premium',
  'netflix': 'Netflix',
  'adobe': 'Adobe',
  'windows': 'Windows',
  'office': 'Office',
};

const _durationLabels = <String, String>{'1m': 'یک ماهه', '3m': 'سه ماهه', '6m': 'شش ماهه', '12m': 'یک ساله', '': ''};

String _productRowLabel(Map<String, dynamic> row) {
  final base = _productLabels['${row['product']}'] ?? '${row['product']}';
  final dur = _durationLabels['${row['duration'] ?? ''}'] ?? '';
  return dur.isEmpty ? base : '$base ($dur)';
}

String _fmtPrice(dynamic n) {
  if (n == null) return '—';
  final v = n is int ? n : int.tryParse('$n') ?? 0;
  return '${faDigits(v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ','))} ت';
}

/// Competitor intelligence: per-competitor websites and Instagram pages, a price matrix, and
/// content gaps Postyar can turn into posts.
class CompetitorsScreen extends StatefulWidget {
  const CompetitorsScreen({super.key, required this.api, required this.brand, required this.onUse});
  final Api api;
  final Brand brand;
  final UseIdea onUse;

  @override
  State<CompetitorsScreen> createState() => _CompetitorsScreenState();
}

class _CompetitorsScreenState extends State<CompetitorsScreen> {
  List<Competitor>? _items;
  List<CompetitorScan>? _scans;
  Timer? _poll;
  bool _starting = false;

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
      final items = await widget.api.competitors(widget.brand.id!);
      final scans = await widget.api.competitorScans(widget.brand.id!);
      if (!mounted) return;
      setState(() {
        _items = items;
        _scans = scans;
      });
      _poll?.cancel();
      if (scans.isNotEmpty && scans.first.isBusy) {
        _poll = Timer(const Duration(seconds: 5), _load);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _save(List<Competitor> items) async {
    try {
      final saved = await widget.api.saveCompetitors(widget.brand.id!, items);
      if (mounted) setState(() => _items = saved);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _startScan() async {
    setState(() => _starting = true);
    try {
      await widget.api.startCompetitorScan(widget.brand.id!);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.status == 409 ? 'یک اسکن در حال انجام است' : e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _editCompetitor([Competitor? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final website = TextEditingController(text: existing?.website ?? '');
    final ig = TextEditingController(text: existing?.instagram ?? '');
    final tg = TextEditingController(text: existing?.telegram ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(existing == null ? 'رقیب جدید' : 'ویرایش رقیب', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام')),
              const SizedBox(height: 10),
              TextField(
                controller: website,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'سایت', hintText: 'example.com'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ig,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'اینستاگرام', hintText: 'username'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tg,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'تلگرام (اختیاری)', hintText: 'username'),
              ),
              const SizedBox(height: 10),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final newIg = ig.text.trim().replaceFirst('@', '');
    final newTg = tg.text.trim().replaceFirst('@', '');
    // Editing the handle by hand makes it manual again; leaving it untouched keeps its verified status.
    final keepIg = existing != null && newIg == existing.instagram;
    final keepTg = existing != null && newTg == existing.telegram;
    final updated = Competitor(
      id: existing?.id ?? '',
      name: name.text.trim(),
      website: website.text.trim(),
      instagram: newIg,
      telegram: newTg,
      notes: notes.text.trim(),
      instagramStatus: keepIg ? existing.instagramStatus : (newIg.isEmpty ? '' : 'manual'),
      instagramEvidence: keepIg ? existing.instagramEvidence : '',
      telegramStatus: keepTg ? existing.telegramStatus : (newTg.isEmpty ? '' : 'manual'),
      telegramEvidence: keepTg ? existing.telegramEvidence : '',
    );
    final items = [...?_items];
    if (existing == null) {
      items.add(updated);
    } else {
      items[items.indexWhere((c) => c.id == existing.id)] = updated;
    }
    await _save(items);
  }

  Future<void> _deleteCompetitor(Competitor c) async {
    await _save([...?_items]..removeWhere((x) => x.id == c.id));
  }

  Future<void> _bulkPaste() async {
    final controller = TextEditingController();
    List<Competitor>? preview;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('افزودن گروهی رقبا', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text('هر خط یک آدرس سایت، پیج اینستاگرام یا کانال تلگرام رقیب را وارد کن.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(hintText: 'parspremium.ir\ninstagram.com/cafearz\n@dicardo_shop'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final items = await widget.api.parseCompetitorsText(widget.brand.id!, controller.text);
                      setSheet(() => preview = items);
                    } on ApiException catch (e) {
                      if (ctx.mounted) showSnack(ctx, e.message);
                    }
                  },
                  child: const Text('پیش‌نمایش'),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  Text('${faDigits(preview!.length)} رقیب پیدا شد:', style: Theme.of(ctx).textTheme.titleSmall),
                  for (final c in preview!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${c.label}${c.website.isNotEmpty ? ' — ${c.website}' : ''}'),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final existing = [...?_items];
                      final known = existing.map((c) => '${c.website}|${c.instagram}').toSet();
                      for (final c in preview!) {
                        if (!known.contains('${c.website}|${c.instagram}')) existing.add(c);
                      }
                      Navigator.pop(ctx);
                      await _save(existing);
                    },
                    child: const Text('ذخیره همه'),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scans = _scans;
    if (items == null || scans == null) return const Center(child: CircularProgressIndicator());
    final latest = scans.where((s) => s.status == 'ready').firstOrNull;
    final busy = scans.isNotEmpty && scans.first.isBusy;
    final failed = scans.isNotEmpty && scans.first.status == 'failed' ? scans.first : null;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SectionTitle(
            'رقبا (${faDigits(items.length)})',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.content_paste_go), tooltip: 'افزودن گروهی', onPressed: _bulkPaste),
                IconButton(icon: const Icon(Icons.add), tooltip: 'افزودن رقیب', onPressed: () => _editCompetitor()),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('هنوز رقیبی اضافه نشده. با دکمه‌ی + یا افزودن گروهی شروع کن.'),
            ),
          for (final c in items) _CompetitorCard(c: c, onTap: () => _editCompetitor(c), onDelete: () => _deleteCompetitor(c)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: items.isEmpty || busy || _starting ? null : _startScan,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar),
            label: Text(busy ? 'در حال اسکن رقبا…' : 'اسکن رقبا'),
          ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'آخرین اسکن ناموفق بود: ${failed.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (latest == null && !busy && items.isNotEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('هنوز اسکنی انجام نشده.', textAlign: TextAlign.center)),
          if (latest != null) ..._report(latest),
        ],
      ),
    );
  }

  List<Widget> _report(CompetitorScan s) {
    final theme = Theme.of(context);
    final names = [for (final c in s.competitors) '${c['name']}'];
    return [
      SectionTitle(
        'گزارش رقبا',
        trailing: Text(
          s.createdAt == null ? '' : faDigits(s.createdAt!.toLocal().toString().substring(0, 16)),
          style: theme.textTheme.labelSmall,
        ),
      ),
      if (s.isPartial)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              const Expanded(child: Text('این اسکن به‌خاطر محدودیت زمانی ناقص است؛ بخشی از رقبا کامل بررسی نشدند.')),
            ],
          ),
        ),
      if (s.priceMatrix.isNotEmpty) ...[
        const SectionTitle('مقایسه‌ی قیمت'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('محصول')),
              for (final n in names) DataColumn(label: Text(n)),
            ],
            rows: [
              for (final row in s.priceMatrix)
                DataRow(cells: [
                  DataCell(Text(_productRowLabel(row))),
                  for (final n in names)
                    DataCell(Text(
                      _fmtPrice((row['prices'] as Map?)?[n]),
                      style: row['cheapest'] == n ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800) : null,
                    )),
                ]),
            ],
          ),
        ),
      ],
      if (s.competitors.isNotEmpty) ...[
        const SectionTitle('پروفایل رقبا'),
        for (final c in s.competitors) _CompetitorReportCard(c: c, positioning: '${s.positioning[c['name']] ?? ''}'),
      ],
      if (s.gaps.isNotEmpty) ...[
        const SectionTitle('خلأهای مبتنی بر داده'),
        for (final g in s.gaps)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text('${g['text'] ?? ''}'),
              subtitle: Text('شواهد: ${(g['evidence'] as List? ?? const []).join('، ')}', style: theme.textTheme.bodySmall),
              trailing: TextButton.icon(
                onPressed: () => widget.onUse(postType: 'educational', topic: '${g['text'] ?? ''}'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('بساز'),
              ),
            ),
          ),
      ],
      if (s.suggestions.isNotEmpty) ...[
        const SectionTitle('ایده‌های عمومی (بدون شاهد مستقیم)'),
        for (final sug in s.suggestions)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(sug),
              trailing: TextButton.icon(
                onPressed: () => widget.onUse(postType: 'educational', topic: sug),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('بساز'),
              ),
            ),
          ),
      ],
      if (s.postIdeas.isNotEmpty) ...[
        const SectionTitle('ایده‌های پست آماده'),
        for (final i in s.postIdeas)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${i['topic'] ?? ''}'),
              subtitle: Text(postTypes['${i['post_type']}'] ?? '${i['post_type']}'),
              trailing: TextButton.icon(
                onPressed: () => widget.onUse(
                  postType: postTypes.containsKey(i['post_type']) ? '${i['post_type']}' : 'educational',
                  topic: '${i['topic'] ?? ''}',
                  mode: i['mode'] == 'carousel' ? 'carousel' : (i['mode'] == 'video' ? 'video' : 'single'),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('بساز'),
              ),
            ),
          ),
      ],
    ];
  }
}

class _CompetitorCard extends StatelessWidget {
  const _CompetitorCard({required this.c, required this.onTap, required this.onDelete});
  final Competitor c;
  final VoidCallback onTap, onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text(c.label.characters.first.toUpperCase())),
      title: Text(c.label),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              [if (c.website.isNotEmpty) c.website, if (c.instagram.isNotEmpty) '@${c.instagram}'].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (c.instagramStatus == 'verified')
            const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.verified, size: 14)),
        ],
      ),
      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
    ),
  );
}

class _CompetitorReportCard extends StatelessWidget {
  const _CompetitorReportCard({required this.c, required this.positioning});
  final Map<String, dynamic> c;
  final String positioning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final website = Map<String, dynamic>.from(c['website'] as Map? ?? {});
    final reachable = website['ok'] == true;
    final signals = Map<String, dynamic>.from(website['signals'] as Map? ?? {});
    final ig = Map<String, dynamic>.from(c['instagram'] as Map? ?? {});
    final discounts = [for (final d in (website['discounts'] as List? ?? const [])) '$d'];
    final igStatus = '${c['instagram_status'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c['name']}', style: theme.textTheme.titleSmall),
            if (positioning.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(positioning)),
            if (!reachable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('سایت این رقیب در دسترس نبود؛ نمادهای اعتماد نامعلوم است', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (reachable && signals['enamad'] == true) const Chip(label: Text('اینماد'), visualDensity: VisualDensity.compact),
                if (reachable && signals['guarantee'] == true) const Chip(label: Text('گارانتی'), visualDensity: VisualDensity.compact),
                if (reachable && signals['instant_delivery'] == true)
                  const Chip(label: Text('تحویل فوری'), visualDensity: VisualDensity.compact),
                for (final d in discounts.take(2))
                  Chip(label: Text(d, overflow: TextOverflow.ellipsis), visualDensity: VisualDensity.compact),
                if (igStatus.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.camera_alt_outlined, size: 14),
                    label: Text(socialStatusLabels[igStatus] ?? igStatus),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: igStatus == 'verified' ? theme.colorScheme.primaryContainer : null,
                  ),
              ],
            ),
            if (ig.isNotEmpty && (ig['post_frequency_30d'] ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.camera_alt_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('${faDigits(ig['post_frequency_30d'] ?? 0)} پست در ۳۰ روز اخیر'),
                  if (ig['partial'] == true) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: const Text('اطلاعات ناقص'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
