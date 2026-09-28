import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> copyText(BuildContext context, String text, {String label = 'کپی شد'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, label);
}

/// Converts Latin digits to Persian digits for display.
String faDigits(Object value) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return '$value'.replaceAllMapped(RegExp(r'\d'), (m) => fa[int.parse(m[0]!)]);
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});
  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'ready' => (const Color(0xFFFFF4E0), const Color(0xFFB45309)),
      'approved' => (const Color(0xFFE6F7EF), const Color(0xFF11774D)),
      'failed' || 'rejected' => (const Color(0xFFFEECEB), const Color(0xFFB42318)),
      _ => (const Color(0xFFF2F4F5), const Color(0xFF475467)),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'queued' || status == 'running') ...[
            SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
            const SizedBox(width: 6),
          ],
          Text(
            statusLabels[status] ?? status,
            style: TextStyle(color: fg, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Small colored label for a content objective (آموزشی، خبری، …).
class TypeBadge extends StatelessWidget {
  const TypeBadge(this.postType, {super.key, this.label});
  final String postType;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = PColors.objective(postType, Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label ?? postTypes[postType] ?? postType,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.subtitle});
  final String text;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Friendly empty/placeholder state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          GradientIcon(icon, size: 52),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(body!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// An English generation prompt: left-to-right, selectable, with a one-tap copy button.
class PromptBlock extends StatefulWidget {
  const PromptBlock({super.key, required this.text, this.label = 'پرامپت انگلیسی', this.collapsedLines = 5});
  final String text;
  final String label;
  final int collapsedLines;

  @override
  State<PromptBlock> createState() => _PromptBlockState();
}

class _PromptBlockState extends State<PromptBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final long = widget.text.length > 320;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 0),
            child: Row(
              children: [
                Icon(Icons.translate, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text(widget.label, style: Theme.of(context).textTheme.labelMedium)),
                TextButton.icon(
                  onPressed: () => copyText(context, widget.text, label: 'پرامپت کپی شد'),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('کپی'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: SelectableText(
              widget.text,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              maxLines: long && !_open ? widget.collapsedLines : null,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Vazirmatn'],
                fontSize: 12.5,
                height: 1.6,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (long)
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_open ? 'بستن' : 'نمایش کامل', style: TextStyle(color: scheme.primary, fontSize: 12)),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: scheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lays children out in a responsive grid (1 column on phones, more on wide screens) inside a ListView.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minTile = 300, this.spacing = 12});
  final List<Widget> children;
  final double minTile, spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = (c.maxWidth / minTile).floor().clamp(1, 4);
      if (cols == 1) {
        return Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
          ],
        );
      }
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}
