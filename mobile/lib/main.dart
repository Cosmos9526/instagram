import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/server_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mobile only, portrait only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final api = await Api.load();
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
      home: api.isConfigured ? HomeScreen(api: api) : ServerScreen(api: api),
    );
  }
}
