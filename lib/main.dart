import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/data_providers.dart';
import 'screens/first_launch_screen.dart';
import 'screens/home_screen_placeholder.dart';
import 'services/app_settings.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AppSettings wraps shared_preferences, which needs its own async init
  // before anything else touches it. Doing this here (rather than inside
  // a provider) means appSettingsProvider can be a plain synchronous
  // Provider below — no AsyncValue handling needed just to read a string.
  final appSettings = await AppSettings.load();

  runApp(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWithValue(appSettings),
      ],
      child: const HeadcountApp(),
    ),
  );
}

class HeadcountApp extends ConsumerWidget {
  const HeadcountApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataDirectory = ref.watch(dataDirectoryProvider);

    return MaterialApp(
      title: 'Headcount',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // No in-app toggle: follow whatever the OS is set to, light or dark.
      themeMode: ThemeMode.system,
      home: dataDirectory == null
          ? const FirstLaunchScreen()
          : const HomeScreenPlaceholder(),
    );
  }
}
