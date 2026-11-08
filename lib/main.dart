import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/history_item.dart';
import 'pages/detection_page.dart';
import 'pages/dictionary_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'providers/history_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_bottom_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.cameraEnabled = true});

  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2864F0);
    final home = HomeShell(cameraEnabled: cameraEnabled);
    return MaterialApp(
      title: 'LatihIsyarat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        fontFamily: 'Roboto',
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2864F0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090D16),
        fontFamily: 'Roboto',
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: SplashScreen(
        nextScreen: home,
        firstLaunchScreen: OnboardingScreen(nextScreen: home),
      ),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.cameraEnabled});

  final bool cameraEnabled;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;
  int _detectionInitialTab = 0;
  bool _detectionBusy = false;

  void _navigate(int index) {
    if (_detectionBusy || index == _selectedIndex) return;
    _detectionInitialTab = 0;
    setState(() => _selectedIndex = index);
  }

  void _openUpload() {
    if (_detectionBusy) return;
    setState(() {
      _selectedIndex = 1;
      _detectionInitialTab = 2;
    });
  }

  Future<void> _saveResult(HistoryItem item) =>
      ref.read(historyProvider.notifier).addHistory(item);

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      0 => HomePage(onNavigate: _navigate, onUploadTap: _openUpload),
      1 => DetectionPage(
        cameraEnabled: widget.cameraEnabled,
        initialTab: _detectionInitialTab,
        onResultSaved: _saveResult,
        onBusyChanged: (busy) {
          if (mounted && busy != _detectionBusy) {
            setState(() => _detectionBusy = busy);
          }
        },
      ),
      2 => const DictionaryPage(),
      _ => const HistoryPage(),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: AppBottomNav(
        currentIndex: _selectedIndex,
        onSelected: _navigate,
        enabled: !_detectionBusy,
      ),
    );
  }
}
