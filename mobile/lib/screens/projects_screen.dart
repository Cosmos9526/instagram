import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';
import 'brand_screen.dart';
import 'profile_screen.dart';
import 'project_screen.dart';
import 'templates_screen.dart';

Color _hex(String? s, Color fallback) {
  try {
    return Color(int.parse('FF${s!.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// The user's projects (one per business/brand).
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.api});
  final Api api;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Brand>? _brands;
  AppUser? _user;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (user, brands) = (await widget.api.me(), await widget.api.brands());
      if (!mounted) return;
      setState(() {
        _user = user;
        _brands = brands;
        _error = null;
      });
    } on ApiException catch (e) {
      if (e.status == 401) return _logout();
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AuthScreen(api: widget.api)),
      (_) => false,
    );
  }

  Future<void> _newProject() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BrandScreen(api: widget.api)),
    );
    if (id == null) return;
    await _load();
    final b = _brands?.where((b) => b.id == id).firstOrNull;
    if (b != null && mounted) _open(b);
  }

  Future<void> _open(Brand b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectScreen(api: widget.api, brand: b),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final brands = _brands;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _user == null
              ? 'پروژه‌ها'
              : 'سلام ${_user!.name.isEmpty ? '' : _user!.name}',
        ),
        actions: [
          IconButton(
            tooltip: 'قالب‌ها',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TemplatesScreen(api: widget.api),
              ),
            ),
          ),
          IconButton(
            tooltip: 'حساب کاربری',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProfileScreen(api: widget.api, onLogout: _logout),
                ),
              );
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: brands == null || brands.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newProject,
              icon: const Icon(Icons.add),
              label: const Text('پروژه‌ی جدید'),
            ),
      body: brands == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('تلاش دوباره'),
                        ),
                      ],
                    ),
            )
          : brands.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rocket_launch_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'اولین پروژه‌ات را بساز',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'هر پروژه یک کسب‌وکار یا برند است: مشخصات، محصولات، مخاطب و برنامه‌ی انتشار خودش را دارد.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _newProject,
                      icon: const Icon(Icons.add),
                      label: const Text('ساخت پروژه'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                children: [
                  for (final b in brands)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(b),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 92,
                              color: _hex(
                                b.colors['primary'],
                                theme.colorScheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.name,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      b.industry,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${faDigits(b.weeklyPlan.values.fold<int>(0, (n, l) => n + l.length))} پست در هفته',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
