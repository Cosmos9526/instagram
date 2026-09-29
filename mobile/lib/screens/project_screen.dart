import '../widgets/choice_field.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'brand_screen.dart';
import 'competitors_screen.dart';
import 'generate_screen.dart';
import 'home_screen.dart';
import 'research_screen.dart';
import 'projects_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';

/// One project: today, create, market, competitors, brand profile. The same bottom navigation on every
/// screen size; content is centered on wide screens.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.api, required this.brand});
  final Api api;
  final Brand brand;

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  late Brand _brand = widget.brand;
  int _tab = 0;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _generateKey = GlobalKey<GenerateScreenState>();

  void _goGenerate({
    required String postType,
    String topic = '',
    String mode = 'single',
    String videoStyle = '',
  }) {
    setState(() => _tab = 1);
    _generateKey.currentState?.prefill(
      postType: postType,
      topic: topic,
      mode: mode,
      videoStyle: videoStyle,
    );
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 0) _homeKey.currentState?.refresh();
  }

  Future<void> _switchProject() async {
    final brands = await widget.api.brands().catchError((_) => <Brand>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<Brand>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Switch business',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Manage businesses'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProjectsScreen(api: widget.api, selectOnly: true),
                  ),
                );
              },
            ),
            for (final b in brands)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: ProjectAvatar(brand: b),
                title: Text(b.name.isEmpty ? 'Untitled business' : b.name),
                subtitle: Text(choiceLabel(b.industry)),
                trailing: b.id == _brand.id
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, b),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.id == _brand.id || !mounted) return;
    await widget.api.selectBrand(picked.id!);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProjectScreen(api: widget.api, brand: picked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        key: _homeKey,
        api: widget.api,
        brand: _brand,
        onCreate: _goGenerate,
        onTab: _selectTab,
      ),
      GenerateScreen(
        key: _generateKey,
        api: widget.api,
        brand: _brand,
        onCreated: () {
          setState(() => _tab = 0);
          _homeKey.currentState?.refresh();
        },
      ),
      ResearchScreen(api: widget.api, brand: _brand, onUse: _goGenerate),
      CompetitorsScreen(api: widget.api, brand: _brand, onUse: _goGenerate),
      BrandScreen(
        api: widget.api,
        brand: _brand,
        embedded: true,
        onSaved: (_) async {
          final fresh = (await widget.api.brands())
              .where((b) => b.id == _brand.id)
              .firstOrNull;
          if (fresh != null && mounted) setState(() => _brand = fresh);
        },
        onDeleted: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ProjectsScreen(api: widget.api)),
          (_) => false,
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfileScreen(
                  api: widget.api,
                  onLogout: () async {
                    await widget.api.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => AuthScreen(api: widget.api),
                      ),
                      (_) => false,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _switchProject,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProjectAvatar(brand: _brand, size: 32),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _brand.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        choiceLabel(_brand.industry),
                        maxLines: 1,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(height: 1.2),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
      body: FadeIndexedStack(index: _tab, children: pages),
      extendBody: true,
      bottomNavigationBar: FloatingNav(
        index: _tab,
        onTap: _selectTab,
        items: const [
          (Icons.today_outlined, Icons.today, 'Home'),
          (Icons.add_circle_outline, Icons.add_circle, 'Create'),
          (Icons.insights_outlined, Icons.insights, 'Research'),
          (Icons.groups_outlined, Icons.groups, 'Rivals'),
          (Icons.storefront_outlined, Icons.storefront, 'Brand'),
        ],
      ),
    );
  }
}

Color _hex(String? s, Color fallback) {
  try {
    return Color(int.parse('FF${s!.replaceFirst('#', '')}', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Rounded square with the project's initial in its brand colors.
class ProjectAvatar extends StatelessWidget {
  const ProjectAvatar({super.key, required this.brand, this.size = 40});
  final Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .3),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            _hex(brand.colors['primary'], scheme.primary),
            _hex(brand.colors['secondary'], PColors.tealDeep),
          ],
        ),
      ),
      child: Text(
        brand.name.isEmpty ? '?' : brand.name.characters.first,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * .42,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
      ),
    );
  }
}
