import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'brand_screen.dart';
import 'generate_screen.dart';
import 'posts_screen.dart';
import 'server_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final Api api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Brand>? _brands;
  Brand? _brand;
  int _tab = 0;
  String? _error;
  final _postsKey = GlobalKey<PostsScreenState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final brands = await widget.api.brands();
      final saved = widget.api.brandId;
      setState(() {
        _brands = brands;
        _brand = brands.where((b) => b.id == saved).firstOrNull ?? brands.firstOrNull;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _editBrand(Brand? brand) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BrandScreen(api: widget.api, brand: brand)),
    );
    if (id != null) {
      await widget.api.setBrandId(id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('تلاش دوباره')),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => ServerScreen(api: widget.api)),
              ),
              child: const Text('تنظیمات سرور'),
            ),
          ]),
        ),
      );
    }
    if (_brands == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final brand = _brand;
    if (brand == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('هشتپا')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.storefront_outlined, size: 64),
              const SizedBox(height: 16),
              const Text('اول کسب‌وکارت رو تعریف کن تا هر روز پست مناسب برات ساخته بشه.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _editBrand(null),
                icon: const Icon(Icons.add),
                label: const Text('تعریف کسب‌وکار'),
              ),
            ]),
          ),
        ),
      );
    }

    final pages = [
      PostsScreen(key: _postsKey, api: widget.api, brand: brand),
      GenerateScreen(
        api: widget.api,
        brand: brand,
        onCreated: () {
          setState(() => _tab = 0);
          _postsKey.currentState?.refresh();
        },
      ),
      BrandScreen(api: widget.api, brand: brand, embedded: true, onSaved: (_) => _load()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(brand.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'new') return _editBrand(null);
              if (v == 'server') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ServerScreen(api: widget.api)));
                return;
              }
              await widget.api.setBrandId(v);
              setState(() => _brand = _brands!.firstWhere((b) => b.id == v));
            },
            itemBuilder: (_) => [
              for (final b in _brands!) PopupMenuItem(value: b.id, child: Text(b.name)),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'new', child: Text('کسب‌وکار جدید')),
              const PopupMenuItem(value: 'server', child: Text('تنظیمات سرور')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 0) _postsKey.currentState?.refresh();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'پست‌ها'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'ساخت'),
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'کسب‌وکار'),
        ],
      ),
    );
  }
}

