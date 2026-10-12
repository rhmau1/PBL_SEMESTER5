import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';

class DictionaryPage extends StatelessWidget {
  const DictionaryPage({super.key});

  static const List<Map<String, String>> _words = [
    {'word': 'Hello', 'image': ''},
    {'word': 'Thank You', 'image': ''},
    {'word': 'Good Bye', 'image': ''},
    {'word': 'Please', 'image': ''},
    {'word': 'Sorry', 'image': ''},
    {'word': 'Yes', 'image': ''},
    {'word': 'No', 'image': ''},
    {'word': 'Help', 'image': ''},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Dictionary',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _words.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
        itemBuilder: (context, index) {
          final item = _words[index];
          return _DictionaryItem(word: item['word']!);
        },
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

class _DictionaryItem extends StatelessWidget {
  final String word;
  const _DictionaryItem({required this.word});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          // TODO: navigate to detail
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Placeholder for sign image
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.sign_language_outlined,
                  color: Color(0xFF9E9E9E),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  word,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
            ],
          ),
        ),
      ),
    );
  }
}
