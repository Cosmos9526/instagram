import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/common.dart';
import 'projects_screen.dart';
import 'server_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api});
  final Api api;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      if (_signup) {
        await widget.api.register(_name.text.trim(), email, _password.text);
      } else {
        await widget.api.login(email, _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ProjectsScreen(api: widget.api)),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'هشتپا',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text('هر روز پست آماده برای اینستاگرام کسب‌وکارت'),
              const SizedBox(height: 32),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('ورود')),
                  ButtonSegment(value: true, label: Text('ثبت‌نام')),
                ],
                selected: {_signup},
                onSelectionChanged: (s) => setState(() => _signup = s.first),
              ),
              const SizedBox(height: 20),
              if (_signup) ...[
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'نام شما',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'ایمیل',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
                validator: (v) =>
                    (v ?? '').contains('@') ? null : 'ایمیل معتبر وارد کنید',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                textDirection: TextDirection.ltr,
                obscureText: _hide,
                autofillHints: [
                  _signup ? AutofillHints.newPassword : AutofillHints.password,
                ],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'رمز عبور',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _hide
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                validator: (v) => _signup && (v ?? '').length < 8
                    ? 'حداقل ۸ حرف'
                    : ((v ?? '').isEmpty ? 'الزامی است' : null),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_signup ? 'ساخت حساب' : 'ورود'),
              ),
              if (!kIsWeb)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ServerScreen(api: widget.api),
                    ),
                  ),
                  child: const Text('تغییر آدرس سرور'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
