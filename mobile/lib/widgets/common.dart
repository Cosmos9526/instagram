import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

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
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      'ready' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'approved' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'failed' || 'rejected' => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == 'queued' || status == 'running') ...[
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
            const SizedBox(width: 6),
          ],
          Text(statusLabels[status] ?? status, style: TextStyle(color: fg, fontSize: 12)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}
