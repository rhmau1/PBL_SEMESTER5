import 'package:flutter/material.dart';

import '../screens/sign_guide_screen.dart';
import 'guide_page.dart';
class DictionaryPage extends StatelessWidget {
  const DictionaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Kamus Isyarat',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Panduan Penggunaan',
            icon: const Icon(
              Icons.help_outline_rounded,
              color: Color(0xFF2864F0),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuidePage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const SafeArea(child: SignGuideScreen()),
    );
  }
}
