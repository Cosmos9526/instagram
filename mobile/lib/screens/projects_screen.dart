import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../theme.dart';
import 'auth_screen.dart';
import 'project_wizard.dart';
import 'profile_screen.dart';
import 'project_screen.dart';
import 'templates_screen.dart';

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
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => AuthScreen(api: widget.api)), (_) => false);
  }

  Future<void> _newProject() async {
    final id = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => ProjectWizard(api: widget.api)));
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
        title: const Text('استودیوی محتوا'),
        actions: [
          IconButton(
            tooltip: 'قالب‌ها و سبک‌های ویدیو',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TemplatesScreen(api: widget.api))),
          ),
          IconButton(
            tooltip: 'حساب کاربری',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(api: widget.api, onLogout: _logout),
                ),
              );
              _load();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: brands == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
                      ],
                    ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: pagePadding(context, maxWidth: 1000, bottom: 40),
                children: [
                  Text(
                    _user == null || _user!.name.trim().isEmpty ? 'سلام' : 'سلام ${_user!.name.trim()}',
                    style: theme.textTheme.headlineSmall,
                  ),
                  Text(
                    brands.isEmpty
                        ? 'اولین کسب‌وکارت را اضافه کن تا هر روز بدانی چه چیزی منتشر کنی.'
                        : 'یک کسب‌وکار را باز کن تا محتوای امروزش را ببینی یا بسازی.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  ResponsiveGrid(
                    minTile: 300,
                    children: [
                      for (final b in brands) _ProjectCard(brand: b, onTap: () => _open(b)),
                      _NewProjectCard(onTap: _newProject, first: brands.isEmpty),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.brand, required this.onTap});
  final Brand brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perWeek = brand.weeklyPlan.values.fold<int>(0, (n, l) => n + l.length);
    final details = [
      if (brand.instagram.isNotEmpty) '@${brand.instagram}',
      if (brand.website.isNotEmpty) brand.website.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ProjectAvatar(brand: brand, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(brand.name.isEmpty ? 'بدون نام' : brand.name, style: theme.textTheme.titleMedium),
                    Text(
                      [
                        brand.industry,
                        if (perWeek > 0) '${faDigits(perWeek)} محتوا در هفته',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap, required this.first});
  final VoidCallback onTap;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.primary.withValues(alpha: .5), width: 1.4),
            color: scheme.primaryContainer.withValues(alpha: .35),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.add, color: scheme.onPrimary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first ? 'افزودن اولین کسب‌وکار' : 'کسب‌وکار جدید',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'با آدرس سایت یا اینستاگرام، بقیه خودکار پر می‌شود',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
