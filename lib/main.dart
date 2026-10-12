import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/history_item.dart';
import 'pages/detection_page.dart';
import 'pages/dictionary_page.dart';
import 'pages/history_page.dart';
import 'pages/home_page.dart';
import 'providers/history_provider.dart';
import 'widgets/app_bottom_nav.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.cameraEnabled = true});

  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E7D32);
    return MaterialApp(
      title: 'LatihIsyarat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        fontFamily: 'Roboto',
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ),
      home: HomeShell(cameraEnabled: cameraEnabled),
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
  bool _detectionBusy = false;

  void _navigate(int index) {
    if (_detectionBusy || index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  Future<void> _saveResult(HistoryItem item) =>
      ref.read(historyProvider.notifier).addHistory(item);

  @override
  Widget build(BuildContext context) {
    final cameraSelected = _selectedIndex == 1;
    final page = switch (_selectedIndex) {
      0 => HomePage(onNavigate: _navigate),
      1 => DetectionPage(
        cameraEnabled: widget.cameraEnabled,
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
      extendBody: cameraSelected,
      body: page,
      bottomNavigationBar: AppBottomNav(
        currentIndex: _selectedIndex,
        onSelected: _navigate,
        enabled: !_detectionBusy,
        cameraOverlay: cameraSelected,
      ),
    );
  }
}
