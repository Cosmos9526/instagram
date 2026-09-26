import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'demo.dart';
import 'screens/home_screen.dart';
import 'screens/server_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mobile only, portrait only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (isDemo) {
    // In-memory settings: the demo never touches browser storage.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'flutter.base_url': '', 'flutter.token': 'demo', 'flutter.brand_id': 'demo'});
  }
  final api = await Api.load();
  if (isDemo) api.client = demoClient();
  runApp(HashtpaApp(api: api));
}

class HashtpaApp extends StatelessWidget {
  const HashtpaApp({super.key, required this.api});
  final Api api;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E7C66);
    return MaterialApp(
      title: 'هشتپا',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: seed,
        fontFamily: 'Vazirmatn',
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      // Phone layout everywhere: in a wide desktop browser the app stays phone-width and centred.
      builder: (context, child) => ColoredBox(
        color: const Color(0xFFE9EEEC),
        child: Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: child),
        ),
      ),
      home: api.isConfigured ? HomeScreen(api: api) : ServerScreen(api: api),
    );
  }
}
