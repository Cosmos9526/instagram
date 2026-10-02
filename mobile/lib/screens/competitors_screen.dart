import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'research_screen.dart' show UseIdea;

class CompetitorsScreen extends StatefulWidget {
  const CompetitorsScreen({
    super.key,
    required this.api,
    required this.brand,
    required this.onUse,
  });
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
  bool _allProducts = false;
  static const _products = [
    'ChatGPT Plus',
    'Claude Max',
    'ChatGPT Pro',
    'Cursor',
    'Higgsfield',
    'Gemini',
    'Claude Pro',
    'Canva',
    'Perplexity',
    'Midjourney',
    'Runway',
    'Kling',
    'Google Flow',
    'Leonardo',
    'Suno',
    'ElevenLabs',
    'CapCut',
    'GitHub Copilot',
    'Notion',
    'Grammarly',
    'Spotify',
  ];
  String? _queryError;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _query.dispose();
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
      if (scans.any((scan) => scan.isBusy)) {
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
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(
        () => _queryError = 'Enter a product name, for example Claude Max.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _starting = true;
      _queryError = null;
    });
    try {
      final scan = await widget.api.searchPrices(widget.brand.id!, query);
      if (!mounted) return;
      setState(() => _scans = [scan, ...?_scans]);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        if (e.status == 422) {
          setState(() => _queryError = e.message);
          return;
        }
        showSnack(
          context,
          e.status == 409 ? 'A scan is already in progress' : e.message,
        );
        if (e.status == 409) await _load();
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopScan(CompetitorScan scan) async {
    try {
      final stopped = await widget.api.cancelCompetitorScan(scan.id);
      if (!mounted) return;
      setState(() {
        _scans = [
          stopped,
          for (final item in _scans ?? <CompetitorScan>[])
            if (item.id != stopped.id) item,
        ];
      });
      _poll?.cancel();
      showSnack(context, 'Search stopped');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
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
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                existing == null ? 'New competitor' : 'Edit competitor',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: website,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  hintText: 'example.com',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ig,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Instagram',
                  hintText: 'username',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tg,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Telegram (optional)',
                  hintText: 'username',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
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
      instagramStatus: keepIg
          ? existing.instagramStatus
          : (newIg.isEmpty ? '' : 'manual'),
      instagramEvidence: keepIg ? existing.instagramEvidence : '',
      telegramStatus: keepTg
          ? existing.telegramStatus
          : (newTg.isEmpty ? '' : 'manual'),
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
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Add competitors in bulk',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter one website, Instagram profile or Telegram channel per line.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    hintText:
                        'parspremium.ir\ninstagram.com/cafearz\n@dicardo_shop',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      final items = await widget.api.parseCompetitorsText(
                        widget.brand.id!,
                        controller.text,
                      );
                      setSheet(() => preview = items);
                    } on ApiException catch (e) {
                      if (ctx.mounted) showSnack(ctx, e.message);
                    }
                  },
                  child: const Text('Preview'),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${uiDigits(preview!.length)} competitors found:',
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                  for (final c in preview!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '• ${c.label}${c.website.isNotEmpty ? ' — ${c.website}' : ''}',
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final existing = [...?_items];
                      final known = existing
                          .map((c) => '${c.website}|${c.instagram}')
                          .toSet();
                      for (final c in preview!) {
                        if (!known.contains('${c.website}|${c.instagram}')) {
                          existing.add(c);
                        }
                      }
                      Navigator.pop(ctx);
                      await _save(existing);
                    },
                    child: const Text('Save all'),
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
    if (items == null) return const Center(child: CircularProgressIndicator());
    final searches = (_scans ?? <CompetitorScan>[])
        .where((s) => s.report['kind'] == 'price_search')
        .toList();
    final latest = searches.firstOrNull;
    final busy = (_scans ?? <CompetitorScan>[]).any((s) => s.isBusy);
    final rows = (latest?.report['results'] as List? ?? const []);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pagePadding(context, maxWidth: 760),
        children: [
          Text(
            'Compare prices',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text('Search a product across all ${items.length} competitors.'),
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            textDirection: contentDirection(_query.text),
            onChanged: (_) => setState(() => _queryError = null),
            onSubmitted: (_) {
              if (!_starting) _startScan();
            },
            decoration: InputDecoration(
              labelText: 'Product name',
              hintText: 'Claude Max, ChatGPT Plus, Cursor…',
              errorText: _queryError,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(child: Text('Popular products')),
              TextButton(
                onPressed: () => setState(() => _allProducts = !_allProducts),
                child: Text(_allProducts ? 'Show less' : 'All 21'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final product
                  in _allProducts ? _products : _products.take(8))
                ActionChip(
                  label: Text(product),
                  onPressed: _starting
                      ? null
                      : () {
                          setState(() {
                            _query.text = product;
                            _queryError = null;
                          });
                          _startScan();
                        },
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _starting || items.isEmpty ? null : _startScan,
            icon: const Icon(Icons.search),
            label: Text(
              _starting
                  ? 'Starting search…'
                  : busy
                  ? 'Search this product'
                  : 'Check prices',
            ),
          ),
          if (latest?.isBusy == true) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _stopScan(latest!),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop search'),
            ),
          ],
          if (latest != null) ...[
            const SizedBox(height: 16),
            Text(
              'Results: ${latest.report['query']}',
              textDirection: contentDirection('${latest.report['query']}'),
            ),
            if (latest.isBusy)
              Text(
                '${latest.report['progress']?['done'] ?? 0} / ${latest.report['progress']?['total'] ?? items.length} checked',
              ),
            if (latest.status == 'failed')
              Text('Search failed: ${latest.error}'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Prices are snapshots. Compare the same plan and duration.',
              ),
            ),
            for (final c in items)
              _resultCard(
                c,
                rows.where((r) => r['competitor_id'] == c.id).firstOrNull,
                busy,
              ),
          ],
          const SizedBox(height: 20),
          ExpansionTile(
            title: Text('Manage competitors (${items.length})'),
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editCompetitor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                  TextButton.icon(
                    onPressed: _bulkPaste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste list'),
                  ),
                ],
              ),
              for (final c in items)
                _CompetitorCard(
                  c: c,
                  onTap: () => _editCompetitor(c),
                  onDelete: () => _deleteCompetitor(c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _durationLabel(String duration) {
    final months = RegExp(r'^(\d+)m$').firstMatch(duration);
    if (months != null) return '${months.group(1)} ماهه';
    return 'مدت اعلام نشده';
  }

  Widget _offerDetail(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );

  Widget _resultCard(Competitor c, dynamic row, bool busy) {
    const labels = {
      'found': 'Price found',
      'stale': 'Last verified price · latest check failed',
      'price_unavailable': 'Product found · price unavailable',
      'not_found': 'Could not verify a matching price',
      'blocked': 'Website blocked automated access · check the source',
      'unreachable': 'Website unavailable',
      'no_website': 'No website saved',
    };
    final matches = row?['matches'] as List? ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.name.isNotEmpty ? c.name : c.website,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              row == null
                  ? (busy ? 'Waiting…' : 'Not checked')
                  : labels[row['status']] ?? 'Unavailable',
            ),
            if (row?['checked_at'] != null)
              Text(
                'Checked: ${DateTime.tryParse(row['checked_at'])?.toLocal().toString().substring(0, 16) ?? row['checked_at']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            for (final p in matches)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${p['name']}',
                      textDirection: contentDirection('${p['name']}'),
                    ),
                    Text(
                      p['price'] == null
                          ? 'Price unavailable'
                          : '${_price(p['price'])}${p['price_max'] != null && p['price_max'] != p['price'] ? ' – ${_price(p['price_max'])}' : ''} Toman',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (p['regular_price'] != null)
                      Text(
                        '${_price(p['regular_price'])} تومان',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if ('${p['plan'] ?? ''}'.isNotEmpty)
                          _offerDetail('${p['plan']}'),
                        _offerDetail(_durationLabel('${p['duration'] ?? ''}')),
                        if (p['account_type'] == 'shared')
                          _offerDetail('اشتراکی'),
                        if (p['account_type'] == 'personal')
                          _offerDetail('شخصی / اختصاصی'),
                        if (p['in_stock'] == true) _offerDetail('موجود'),
                        if (p['in_stock'] == false) _offerDetail('ناموجود'),
                        if (p['price_kind'] == 'range')
                          _offerDetail('بازهٔ قیمت گزینه‌ها'),
                      ],
                    ),
                    if (p['price'] == null && p['evidence'] != null)
                      Text(
                        '${p['evidence']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () async {
                          final uri = Uri.tryParse('${p['url']}');
                          if (uri != null &&
                              ['http', 'https'].contains(uri.scheme)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: const Text('View source'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _price(dynamic n) =>
      '$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _CompetitorCard extends StatelessWidget {
  const _CompetitorCard({
    required this.c,
    required this.onTap,
    required this.onDelete,
  });
  final Competitor c;
  final VoidCallback onTap, onDelete;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        child: Text(c.label.characters.first.toUpperCase()),
      ),
      title: Text(c.label),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              [
                if (c.website.isNotEmpty) c.website,
                if (c.instagram.isNotEmpty) '@${c.instagram}',
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (c.instagramStatus == 'verified')
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.verified, size: 14),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    ),
  );
}
