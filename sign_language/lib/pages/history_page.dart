import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  static const List<Map<String, String>> _historyItems = [
    {'gesture': 'C', 'accuracy': '88,3 %', 'date': '2026-09-09', 'time': '18:23'},
    {'gesture': 'B', 'accuracy': '88,3 %', 'date': '2026-09-09', 'time': '18:23'},
    {'gesture': 'C', 'accuracy': '88,3 %', 'date': '2026-09-09', 'time': '18:23'},
    {'gesture': 'A', 'accuracy': '91,5 %', 'date': '2026-09-08', 'time': '10:05'},
    {'gesture': 'M', 'accuracy': '95,0 %', 'date': '2026-09-08', 'time': '09:47'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'History',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined,
                color: Color(0xFF9E9E9E)),
            tooltip: 'Hapus semua',
            onPressed: () {
              // TODO: clear history
            },
          ),
        ],
      ),
      body: _historyItems.isEmpty
          ? const Center(
              child: Text(
                'Belum ada riwayat deteksi',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _historyItems.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
              itemBuilder: (context, index) {
                final item = _historyItems[index];
                return _HistoryItem(
                  gesture: item['gesture']!,
                  accuracy: item['accuracy']!,
                  date: item['date']!,
                  time: item['time']!,
                );
              },
            ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final String gesture;
  final String accuracy;
  final String date;
  final String time;

  const _HistoryItem({
    required this.gesture,
    required this.accuracy,
    required this.date,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Placeholder thumbnail
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    gesture,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF616161),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$gesture – $accuracy',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$date  $time',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
