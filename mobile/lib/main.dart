import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'demo.dart';
import 'screens/auth_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/server_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Mobile only, portrait only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (isDemo) {
    // In-memory settings: the demo never touches browser storage.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'flutter.base_url': ''});
  }
  final api = await Api.load();
  if (isDemo) api.client = demoClient();
  runApp(PostyarApp(api: api));
}

class PostyarApp extends StatelessWidget {
  const PostyarApp({super.key, required this.api});
  final Api api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'استودیوی محتوا',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: child!,
          ),
        ),
      ),
      home: startScreen(api),
    );
  }
}

/// Where the app starts: server address (native only) → login → projects.
Widget startScreen(Api api) {
  if (!api.hasServer) return ServerScreen(api: api);
  if (!api.isLoggedIn) return AuthScreen(api: api);
  return ProjectsScreen(api: api);
}
