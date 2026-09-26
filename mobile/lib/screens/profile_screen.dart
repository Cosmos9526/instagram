import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user;
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.me().then((u) {
      if (!mounted) return;
      setState(() => _user = u);
      _name.text = u.name;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final pw = _password.text;
      if (pw.isNotEmpty && pw.length < 8) {
        throw ApiException('رمز جدید حداقل ۸ حرف');
      }
      final u = await widget.api.updateMe(
        name: _name.text.trim(),
        password: pw.isEmpty ? null : pw,
      );
      _password.clear();
      if (!mounted) return;
      setState(() => _user = u);
      showSnack(context, 'ذخیره شد');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حساب کاربری')),
    body: _user == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alternate_email),
                title: Text(
                  _user!.email,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                ),
                subtitle: const Text('ایمیل'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'نام'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رمز جدید (اختیاری)',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('ذخیره'),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('خروج از حساب'),
              ),
            ],
          ),
  );
}
