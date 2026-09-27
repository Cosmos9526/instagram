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
      title: 'Postyar',
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
      // Phone layout everywhere: in a wide desktop browser the app stays phone-width and centred.
      builder: (context, child) {
        // Phone layout everywhere: the app lives in a centred column at most 480 wide, and MediaQuery reports
        // that column (not the whole browser window) so every screen sizes itself correctly.
        final mq = MediaQuery.of(context);
        final width = mq.size.width.clamp(0.0, 480.0);
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: SizedBox(
              width: width,
              child: MediaQuery(
                data: mq.copyWith(size: Size(width, mq.size.height)),
                child: child!,
              ),
            ),
          ),
        );
      },
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
