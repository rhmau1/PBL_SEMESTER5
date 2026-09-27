import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'pages/detection_page.dart';
import 'pages/dictionary_page.dart';
import 'pages/history_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sign Language Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      initialRoute: '/home',
      routes: {
        '/home': (context) => const HomePage(),
        '/detection': (context) => const DetectionPage(),
        '/dictionary': (context) => const DictionaryPage(),
        '/history': (context) => const HistoryPage(),
      },
    );
  }
}
