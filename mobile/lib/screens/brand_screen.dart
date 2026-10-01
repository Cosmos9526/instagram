import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/choice_field.dart';
import '../widgets/common.dart';

const brandPalettes = <List<String>>[
  ['#0E7C66', '#F4B400', '#FFFFFF', '#111111'],
  ['#6B3E26', '#F2C14E', '#FFF8F0', '#2B1B12'],
  ['#1F3A93', '#FF6B6B', '#F7F9FC', '#0B1B3F'],
  ['#111111', '#E63946', '#FFFFFF', '#111111'],
  ['#5B2A86', '#F7B801', '#FBF7FF', '#1E0B33'],
  ['#2A9D8F', '#E76F51', '#FDFBF7', '#1D3557'],
];

Color hexColor(String value) =>
    Color(int.parse('FF${value.replaceFirst('#', '')}', radix: 16));

class BrandScreen extends StatefulWidget {
  const BrandScreen({
    super.key,
    required this.api,
    this.brand,
    this.embedded = false,
    this.onSaved,
    this.onDeleted,
  });
  final Api api;
  final Brand? brand;
  final bool embedded;
  final void Function(String id)? onSaved;
  final VoidCallback? onDeleted;

  @override
  State<BrandScreen> createState() => _BrandScreenState();
}

class _BrandScreenState extends State<BrandScreen> {
  final _form = GlobalKey<FormState>();
  late Brand _brand;
  late Map<String, TextEditingController> _fields;
  bool _saving = false, _syncing = false;
  List<String> _evidence = [];

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(BrandScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand?.id != widget.brand?.id) _reset();
  }

  void _reset() {
    _brand = widget.brand == null
        ? Brand()
        : Brand.fromJson({'id': widget.brand!.id, ...widget.brand!.toJson()});
    TextEditingController field(String value) =>
        TextEditingController(text: value);
    _fields = {
      'name': field(_brand.name),
      'website': field(_brand.website),
      'instagram': field(_brand.instagram),
      'description': field(_brand.description),
      'audience': field(_brand.audience),
      'tone': field(_brand.tone),
      'cta': field(_brand.cta),
    };
  }

  void _readFields() {
    _brand
      ..name = _fields['name']!.text.trim()
      ..website = _fields['website']!.text.trim()
      ..instagram = _fields['instagram']!.text.trim().replaceFirst('@', '')
      ..description = _fields['description']!.text.trim()
      ..audience = _fields['audience']!.text.trim()
      ..tone = _fields['tone']!.text.trim()
      ..cta = _fields['cta']!.text.trim();
  }

  Future<void> _save({bool quiet = false}) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    _readFields();
    if (_brand.industry.isEmpty) {
      showSnack(context, 'Choose a business type');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await widget.api.saveBrand(_brand);
      _brand.id = id;
      if (!mounted) return;
      if (!quiet) showSnack(context, 'Brand knowledge saved');
      widget.onSaved?.call(id);
      if (!widget.embedded) Navigator.of(context).pop(id);
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sync() async {
    _readFields();
    if (_brand.website.isEmpty && _brand.instagram.isEmpty) {
      showSnack(context, 'Add your website or Instagram first');
      return;
    }
    setState(() => _syncing = true);
    try {
      final result = await widget.api.analyze(_brand.website, _brand.instagram);
      final profile = Map<String, dynamic>.from(
        result['profile'] as Map? ?? const {},
      );
      String value(String key) => '${profile[key] ?? ''}'.trim();
      for (final key in ['name', 'description', 'audience', 'tone', 'cta']) {
        if (value(key).isNotEmpty) _fields[key]?.text = value(key);
      }
      if (value('industry').isNotEmpty) _brand.industry = value('industry');
      _brand.products = [
        for (final item in profile['products'] as List? ?? const [])
          if (item is Map) Product.fromJson(Map<String, dynamic>.from(item)),
      ];
      if (profile['colors'] is Map && (profile['colors'] as Map).isNotEmpty) {
        _brand.colors = {
          for (final entry in (profile['colors'] as Map).entries)
            '${entry.key}': '${entry.value}',
        };
      }
      _brand.hashtags = [
        for (final tag in profile['hashtags'] as List? ?? const []) '$tag',
      ];
      _brand.forbiddenTopics = [
        for (final topic in profile['forbidden_topics'] as List? ?? const [])
          '$topic',
      ];
      _evidence = [
        for (final line in result['evidence'] as List? ?? const []) '$line',
      ];
      _readFields();
      if (!mounted) return;
      setState(() {});
      // A source refresh is already an explicit save action. Persist its trusted
      // result directly so an unrelated incomplete manual field cannot discard
      // a catalog that was successfully discovered.
      final id = await widget.api.saveBrand(_brand);
      _brand.id = id;
      widget.onSaved?.call(id);
      if (mounted) {
        showSnack(
          context,
          _brand.products.isEmpty
              ? 'Business details refreshed; no catalog was found'
              : '${_brand.products.length} products and services synced',
        );
      }
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Widget _input(
    String key,
    String label, {
    String? helper,
    String? hint,
    int lines = 1,
    bool required = false,
    bool ltr = false,
  }) => TextFormField(
    controller: _fields[key],
    textDirection: ltr
        ? TextDirection.ltr
        : contentDirection(_fields[key]!.text),
    minLines: lines,
    maxLines: lines,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      alignLabelWithHint: lines > 1,
    ),
    validator: required
        ? (value) => (value ?? '').trim().isEmpty ? 'Required' : null
        : null,
  );

  Widget _panel(Widget child, {Color? color}) => Card(
    margin: EdgeInsets.zero,
    color: color,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final content = Form(
      key: _form,
      child: ListView(
        padding: pagePadding(context, maxWidth: 760),
        children: [
          Text(
            'Brand knowledge',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'The facts and instructions used to write every Rahboom prompt.',
          ),
          const SizedBox(height: 16),
          _sources(context),
          const SizedBox(height: 12),
          _business(context),
          const SizedBox(height: 12),
          _contentRules(context),
          const SizedBox(height: 12),
          _visualIdentity(context),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving || _syncing ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save brand knowledge'),
          ),
          if (widget.embedded && _brand.id != null) ...[
            const SizedBox(height: 24),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete business'),
            ),
          ],
          const SizedBox(height: 100),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brand == null ? 'New business' : 'Brand knowledge'),
      ),
      body: content,
    );
  }

  Widget _sources(BuildContext context) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.sync, color: Color(0xFF11774D)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Keep Rahboom up to date',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'We read these sources to refresh your offers, audience and visual identity.',
        ),
        const SizedBox(height: 16),
        _input('website', 'Website', hint: 'https://rahboom.com', ltr: true),
        const SizedBox(height: 12),
        _input('instagram', 'Instagram', hint: 'rahboomshop', ltr: true),
        if (_evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final line in _evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF11774D),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(line, textDirection: contentDirection(line)),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _syncing || _saving ? null : _sync,
          icon: _syncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search),
          label: Text(_syncing ? 'Reading sources…' : 'Refresh from sources'),
        ),
      ],
    ),
    color: const Color(0xFFF0F9F5),
  );

  Widget _business(BuildContext context) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What you sell', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'These facts prevent invented claims and select the offer used in sales content.',
        ),
        const SizedBox(height: 16),
        _input('name', 'Business name', required: true),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: industryOptions.contains(_brand.industry)
              ? _brand.industry
              : null,
          decoration: const InputDecoration(labelText: 'Business type'),
          items: [
            for (final option in industryOptions)
              DropdownMenuItem(value: option, child: Text(choiceLabel(option))),
          ],
          onChanged: (value) => setState(() => _brand.industry = value ?? ''),
          validator: (_) => _brand.industry.isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        _input(
          'description',
          'What Rahboom does',
          helper:
              'Used as factual context in news, education and sales prompts.',
          lines: 4,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Detected offers',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text('${_brand.products.length} found'),
          ],
        ),
        const SizedBox(height: 8),
        if (_brand.products.isEmpty)
          const Text(
            'No catalog detected. Refresh after checking the website address.',
          )
        else ...[
          for (final product in _brand.products.take(4))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sell_outlined),
              title: Text(
                product.name,
                textDirection: contentDirection(product.name),
              ),
              subtitle: product.desc.isEmpty
                  ? null
                  : Text(
                      product.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: contentDirection(product.desc),
                    ),
            ),
          if (_brand.products.length > 4)
            TextButton(
              onPressed: _showOffers,
              child: Text('View all ${_brand.products.length} offers'),
            ),
        ],
      ],
    ),
  );

  Widget _contentRules(BuildContext context) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Content instructions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'These lines directly shape every generated script and caption.',
        ),
        const SizedBox(height: 16),
        _input(
          'audience',
          'Who should this content convince?',
          helper: 'Used to choose examples, vocabulary and objections.',
          lines: 3,
        ),
        const SizedBox(height: 12),
        _input(
          'tone',
          'How should Rahboom sound?',
          helper: 'Used for dialogue, captions and headlines.',
          lines: 2,
        ),
        const SizedBox(height: 12),
        _input(
          'cta',
          'What should viewers do next?',
          helper: 'Used in the final two-second card and caption.',
          lines: 2,
        ),
        const SizedBox(height: 16),
        Text('Never include', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in forbiddenOptions)
              FilterChip(
                label: Text(choiceLabel(option)),
                selected: _brand.forbiddenTopics.contains(option),
                onSelected: (selected) => setState(() {
                  selected
                      ? _brand.forbiddenTopics.add(option)
                      : _brand.forbiddenTopics.remove(option);
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'fa', label: Text('Persian content')),
            ButtonSegment(value: 'en', label: Text('English content')),
          ],
          selected: {_brand.language},
          onSelectionChanged: (value) =>
              setState(() => _brand.language = value.first),
        ),
      ],
    ),
  );

  Widget _visualIdentity(BuildContext context) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Visual identity', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Used for covers, cards and final frames.'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final palette in brandPalettes)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(
                  () => _brand.colors = {
                    'primary': palette[0],
                    'secondary': palette[1],
                    'bg': palette[2],
                    'text': palette[3],
                  },
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      width: 2,
                      color:
                          _brand.colors['primary'] == palette[0] &&
                              _brand.colors['secondary'] == palette[1]
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in palette.take(3))
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: hexColor(color),
                            border: Border.all(color: Colors.black12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _showOffers() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .75,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Detected offers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text('Synced from your website and used in sales prompts.'),
            const SizedBox(height: 12),
            for (final product in _brand.products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: Text(
                  product.name,
                  textDirection: contentDirection(product.name),
                ),
                subtitle: product.desc.isEmpty
                    ? null
                    : Text(
                        product.desc,
                        textDirection: contentDirection(product.desc),
                      ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete business'),
        content: Text(
          '“${_brand.name}” and all its posts and research will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteBrand(_brand.id!);
      widget.onDeleted?.call();
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message);
    }
  }
}
