import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../widgets/common.dart';

/// Native apps only: the address of the Postyar server. (The PWA uses its own address.)
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.api});
  final Api api;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final _url = TextEditingController(
    text: widget.api.baseUrl.isEmpty ? 'https://' : widget.api.baseUrl,
  );
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.api.saveServer(_url.text);
    try {
      await widget.api.catalog();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => startScreen(widget.api)),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('آدرس سرور')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('آدرس سرور Postyar را وارد کنید.'),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'آدرس سرور',
            hintText: 'https://postyar.example.com',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('ادامه'),
        ),
      ],
    ),
  );
}
