import 'package:flutter/material.dart';

import '../models.dart';

/// Edits the text of a rendered post. Returns the new content map; the server re-renders for free.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.post});
  final Post post;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _Field {
  _Field(this.label, String value, this.write, {this.lines = 1}) : controller = TextEditingController(text: value);
  final String label;
  final TextEditingController controller;
  final void Function(Map<String, dynamic> content, String value) write;
  final int lines;
}

const _slotLabels = {
  'kicker': 'برچسب بالا',
  'headline': 'تیتر',
  'body': 'متن',
  'cta': 'دکمه‌ی دعوت به اقدام',
  'badge': 'نشان (مثلاً ٪۲۰)',
};

class _EditScreenState extends State<EditScreen> {
  late final Map<String, dynamic> _content = _deepCopy(widget.post.content);
  late final List<_Field> _fields = _buildFields();

  static Map<String, dynamic> _deepCopy(Map m) => {
        for (final e in m.entries)
          '${e.key}': switch (e.value) {
            Map v => _deepCopy(v),
            List v => [for (final x in v) x is Map ? _deepCopy(x) : x],
            var v => v,
          }
      };

  List<_Field> _slotFields(String prefix, Map slots, void Function(String k, String v) set) => [
        for (final key in _slotLabels.keys)
          if (slots[key] is String)
            _Field('$prefix${_slotLabels[key]}', slots[key] as String, (_, v) => set(key, v),
                lines: key == 'body' ? 4 : 2),
      ];

  List<_Field> _buildFields() {
    final c = _content;
    final fields = <_Field>[];
    if (widget.post.mode == 'carousel') {
      final cover = c['cover'] as Map;
      fields.addAll(_slotFields('کاور: ', cover, (k, v) => cover[k] = v));
      final bodies = c['body'] as List;
      for (var i = 0; i < bodies.length; i++) {
        final b = bodies[i] as Map;
        fields.addAll(_slotFields('اسلاید ${i + 2}: ', b, (k, v) => b[k] = v));
      }
      final cta = c['cta'] as Map;
      fields.addAll(_slotFields('اسلاید آخر: ', cta, (k, v) => cta[k] = v));
    } else {
      final slots = c['slots'] as Map;
      fields.addAll(_slotFields('', slots, (k, v) => slots[k] = v));
      if (slots['items'] is List) {
        fields.add(_Field('موارد لیست (هر خط یک مورد)', (slots['items'] as List).join('\n'),
            (_, v) => slots['items'] = v.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
            lines: 5));
      }
    }
    fields.add(_Field('کپشن', '${c['caption'] ?? ''}', (m, v) => m['caption'] = v, lines: 6));
    return fields;
  }

  void _save() {
    for (final f in _fields) {
      f.write(_content, f.controller.text.trim());
    }
    Navigator.of(context).pop(_content);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('ویرایش متن'),
          actions: [TextButton(onPressed: _save, child: const Text('ذخیره'))],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _fields.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, i) => TextField(
            controller: _fields[i].controller,
            minLines: 1,
            maxLines: _fields[i].lines,
            decoration: InputDecoration(labelText: _fields[i].label),
          ),
        ),
      );
}
