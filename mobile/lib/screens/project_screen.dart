import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'brand_screen.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(_brand.name)),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) _postsKey.currentState?.refresh();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'پست‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'ساخت',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'بازار',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'تنظیمات',
          ),
        ],
      ),
    );
  }
}
