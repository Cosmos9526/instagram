import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// First run: server address + admin token.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.api});
  final Api api;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late final _url = TextEditingController(text: widget.api.baseUrl.isEmpty ? 'https://' : widget.api.baseUrl);
  late final _token = TextEditingController(text: widget.api.token);
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await widget.api.saveServer(_url.text, _token.text);
      await widget.api.brands(); // verifies both URL and token
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
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
        appBar: AppBar(title: const Text('اتصال به سرور')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('آدرس سرور هشتپا و توکن مدیریت (ADMIN_TOKEN) را وارد کنید.'),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'آدرس سرور', hintText: 'https://hashtpa.example.com'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            textDirection: TextDirection.ltr,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'توکن'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator()) : const Text('اتصال'),
          ),
        ]),
      );
}
