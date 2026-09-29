import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
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
    if (_busy || !_form.currentState!.validate()) return;
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
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _form_(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        children: [
          Text(
            _signup ? 'Create account' : 'Welcome back',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _signup
                ? 'Set up your account to get started.'
                : 'Sign in to your content workspace.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Sign up')),
            ],
            selected: {_signup},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() => _signup = s.first),
          ),
          const SizedBox(height: 20),
          if (_signup) ...[
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Your name',
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
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            validator: (v) =>
                (v ?? '').contains('@') ? null : 'Enter a valid email',
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
              labelText: 'Password',
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
                ? 'At least 8 characters'
                : ((v ?? '').isEmpty ? 'Required' : null),
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
                : Text(_signup ? 'Create account' : 'Sign in'),
          ),
          if (!kIsWeb)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ServerScreen(api: widget.api),
                ),
              ),
              child: const Text('Change server'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            const Expanded(child: _BrandPanel()),
            SizedBox(
              width: 520,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _form_(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _BrandPanel(compact: true),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _form_(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Product introduction: gradient panel beside the form on wide screens, a compact banner on phones.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const points = [
      (Icons.today_outlined, 'Plan what to publish each day'),
      (Icons.insights_outlined, 'Research your market and competitors'),
      (
        Icons.movie_creation_outlined,
        'Create posts, carousels and video briefs',
      ),
    ];
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 56),
      decoration: BoxDecoration(
        color: PColors.forest,
        borderRadius: compact ? BorderRadius.circular(24) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 40 : 56,
            height: compact ? 40 : 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: compact ? 22 : 30,
            ),
          ),
          SizedBox(height: compact ? 14 : 28),
          Text(
            'Content Studio',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 22 : 38,
              fontWeight: FontWeight.w900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your daily content workspace',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .85),
              fontSize: compact ? 14 : 18,
              height: 1.6,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 36),
            for (final (icon, text) in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Icon(icon, color: PColors.tealBright),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
