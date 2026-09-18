import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'features/about/about_screen.dart';
import 'features/collection/collection_dashboard_screen.dart';
import 'features/scanner/scanner_screen.dart';
import 'features/sets/sets_list_screen.dart';
import 'features/settings/settings_screen.dart';
import 'state/providers.dart';
import 'theme.dart';
import 'widgets/themed_background.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const StarTrekCcgApp(),
    ),
  );
}

class StarTrekCcgApp extends ConsumerWidget {
  const StarTrekCcgApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeStyle = ref.watch(appThemeStyleProvider);
    return MaterialApp(
      title: 'Kivas Fajo',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(themeStyle),
      themeMode: themeMode,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return isDark ? ThemedBackground(style: themeStyle, child: child!) : child!;
      },
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _scanTabIndex = 2;

  static const _titles = ['Sets', 'My Collection', 'Scan a Card', 'About'];
  static const _screens = [
    SetsListScreen(),
    CollectionDashboardScreen(),
    ScannerScreen(),
    AboutScreen(),
  ];

  // The Scan tab lives inside an IndexedStack (kept mounted at all times to
  // preserve its state across tab switches), so its own initState/dispose
  // won't fire per visit -- the screen staying awake has to be driven from
  // here, by whether the Scan tab is the one currently selected.
  void _selectTab(int i) {
    setState(() => _index = i);
    WakelockPlus.toggle(enable: i == _scanTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'Sets'),
          NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), selectedIcon: Icon(Icons.collections_bookmark), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'About'),
        ],
      ),
    );
  }
}
