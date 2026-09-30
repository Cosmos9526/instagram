import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
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
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.api.me();
      if (!mounted) return;
      _name.text = user.name;
      setState(() => _user = user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your profile');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final password = _password.text;
    if (password.isNotEmpty && password.length < 8) {
      showSnack(context, 'New password must have at least 8 characters');
      return;
    }
    setState(() => _busy = true);
    try {
      final user = await widget.api.updateMe(
        name: _name.text.trim(),
        password: password.isEmpty ? null : password,
      );
      _password.clear();
      if (!mounted) return;
      setState(() => _user = user);
      showSnack(context, 'Profile saved');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need your email and password to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _user == null) {
      return ListView(
        padding: pagePadding(context, maxWidth: 640),
        children: [
          EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Profile unavailable',
            body: _error ?? 'Could not load your profile',
            action: FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }
    final user = _user!;
    final initial =
        (user.name.trim().isNotEmpty ? user.name.trim() : user.email)
            .characters
            .first
            .toUpperCase();
    return ListView(
      padding: pagePadding(context, maxWidth: 640),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: PColors.mint,
                  foregroundColor: PColors.greenDark,
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.trim().isEmpty ? 'Your account' : user.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user.email,
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle(
          'Personal details',
          subtitle: 'Update the name shown in your workspace.',
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: user.email,
                  readOnly: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email),
                    helperText: 'Email cannot be changed here.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle(
          'Security',
          subtitle: 'Leave the password empty to keep your current password.',
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _password,
              obscureText: !_showPassword,
              enableSuggestions: false,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline),
                helperText: 'At least 8 characters',
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (!_busy) _save();
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_busy ? 'Saving…' : 'Save changes'),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _confirmSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
