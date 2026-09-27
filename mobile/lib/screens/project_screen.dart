import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'brand_screen.dart';
import 'competitors_screen.dart';
import 'generate_screen.dart';
import 'posts_screen.dart';
import 'research_screen.dart';

/// One project: posts, create, market research, settings.
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
  final _postsKey = GlobalKey<PostsScreenState>();
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      PostsScreen(key: _postsKey, api: widget.api, brand: _brand),
      GenerateScreen(
        key: _generateKey,
        api: widget.api,
        brand: _brand,
        onCreated: () {
          setState(() => _tab = 0);
          _postsKey.currentState?.refresh();
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
        onDeleted: () => Navigator.of(context).pop(),
      ),
    ];
    const destinations = [
      (Icons.grid_view_outlined, Icons.grid_view_rounded, 'محتواها'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome, 'ساخت محتوا'),
      (Icons.insights_outlined, Icons.insights, 'رصد بازار'),
      (Icons.groups_outlined, Icons.groups, 'رقبا'),
      (Icons.tune_outlined, Icons.tune, 'پروفایل برند'),
    ];
    void selectTab(int i) {
      setState(() => _tab = i);
      if (i == 0) _postsKey.currentState?.refresh();
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = FadeIndexedStack(index: _tab, children: pages);
    return Scaffold(
      appBar: AppBar(title: Text(_brand.name)),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 210,
                  selectedIndex: _tab,
                  onDestinationSelected: selectTab,
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: Icon(item.$1),
                        selectedIcon: Icon(item.$2),
                        label: Text(item.$3),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : FloatingNav(
              index: _tab,
              onTap: selectTab,
              items: const [
                (Icons.grid_view_outlined, Icons.grid_view_rounded, 'محتواها'),
                (Icons.auto_awesome_outlined, Icons.auto_awesome, 'ساخت'),
                (Icons.insights_outlined, Icons.insights, 'بازار'),
                (Icons.groups_outlined, Icons.groups, 'رقبا'),
                (Icons.tune_outlined, Icons.tune, 'پروفایل'),
              ],
            ),
    );
  }
}
