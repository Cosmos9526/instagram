import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StyleSelection {
  const StyleSelection(this.style, this.prompt);
  final PromptStyle style;
  final String prompt;
}

class StyleLibraryScreen extends StatefulWidget {
  const StyleLibraryScreen({
    super.key,
    required this.api,
    required this.brand,
    this.initialBrief = '',
    this.initialKind = 'video',
  });
  final Api api;
  final Brand brand;
  final String initialBrief, initialKind;
  @override
  State<StyleLibraryScreen> createState() => _StyleLibraryScreenState();
}

class _StyleLibraryScreenState extends State<StyleLibraryScreen> {
  late final TextEditingController _brief;
  late String _kind;
  Catalog? _catalog;
  PromptStyle? _selected;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _brief = TextEditingController(text: widget.initialBrief);
    _kind = widget.initialKind;
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final catalog = await widget.api.catalog();
      if (mounted) setState(() => _catalog = catalog);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load styles. Please retry.');
      }
    }
  }

  @override
  void dispose() {
    _brief.dispose();
    super.dispose();
  }

  String get _prompt =>
      _selected!.compose(_brief.text.trim(), widget.brand.name);
  bool get _ready => _selected != null && _brief.text.trim().isNotEmpty;

  Future<void> _copy({bool cover = false}) async {
    await Clipboard.setData(
      ClipboardData(
        text: _selected!.compose(
          _brief.text.trim(),
          widget.brand.name,
          cover: cover,
        ),
      ),
    );
    if (mounted) {
      showSnack(
        context,
        cover ? 'Cover prompt copied' : 'Complete prompt copied',
      );
    }
  }

  Future<void> _openTool() async {
    final url = _kind == 'video'
        ? 'https://huggingface.co/spaces/Lightricks/LTX-2-3'
        : 'https://huggingface.co/spaces/black-forest-labs/FLUX.1-schnell';
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        showSnack(context, 'Could not open the tool. Try again.');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the tool. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = (_catalog?.promptStyles ?? <PromptStyle>[])
        .where(
          (s) =>
              s.kind == _kind &&
              '${s.name} ${s.nameFa} ${s.description}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Style library')),
      body: ListView(
        padding: pagePadding(context, maxWidth: 720),
        children: [
          const Text('Your prompt + a style → a complete brief to copy.'),
          const SizedBox(height: 16),
          TextField(
            controller: _brief,
            minLines: 3,
            maxLines: 8,
            textDirection: contentDirection(_brief.text),
            textAlign: contentDirection(_brief.text) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Your prompt or idea',
              hintText:
                  'Paste your prompt, exact Persian dialogue, or the scene you want.',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                'video': 'Video · 10 seconds',
                'image': 'Image / cover',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected: (_) => setState(() {
                    _kind = entry.key;
                    _selected = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Find a style',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ] else if (_catalog == null)
            const Center(child: CircularProgressIndicator())
          else if (styles.isEmpty)
            const Text('No matching style. Try another search.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in styles)
                  ChoiceChip(
                    label: Text(style.name),
                    selected: _selected?.id == style.id,
                    onSelected: (_) => setState(() => _selected = style),
                  ),
              ],
            ),
          if (_selected != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selected!.name, style: theme.textTheme.titleMedium),
                    Text(_selected!.nameFa, textDirection: TextDirection.rtl),
                    const SizedBox(height: 8),
                    Text(_selected!.description),
                    const SizedBox(height: 8),
                    Text(
                      _selected!.provenance,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (!_ready)
                      const Text(
                        'Add your prompt above to prepare the complete brief.',
                      )
                    else
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('View complete prompt'),
                        children: [
                          SelectableText(
                            _prompt,
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _ready ? _copy : null,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy complete prompt'),
                ),
                OutlinedButton.icon(
                  onPressed: _ready ? () => _copy(cover: true) : null,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Copy cover prompt'),
                ),
                OutlinedButton.icon(
                  onPressed: _ready
                      ? () => Navigator.of(
                          context,
                        ).pop(StyleSelection(_selected!, _prompt))
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Use in Create'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Try ${_kind == 'video' ? 'LTX 2.3' : 'FLUX.1 Schnell'} on Hugging Face',
              style: theme.textTheme.titleSmall,
            ),
            const Text(
              'External demo. Copy the prompt, open the tool and paste it there. '
              'Free usage has queues and daily limits; a login may be required. '
              'This does not generate media inside this app.',
            ),
            if (_kind == 'video')
              const Text(
                'Check dialogue and lip sync before publishing. '
                'Add the original logo and the 2-second end card in your editor if needed.',
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openTool,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open external demo'),
            ),
          ],
        ],
      ),
    );
  }
}
