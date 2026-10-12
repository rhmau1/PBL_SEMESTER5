import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.enabled = true,
    this.cameraOverlay = false,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final bool enabled;
  final bool cameraOverlay;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: enabled ? onSelected : null,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: cameraOverlay
          ? const Color(0xFF80DB91)
          : const Color(0xFF2E7D32),
      unselectedItemColor: cameraOverlay
          ? Colors.white70
          : const Color(0xFF757575),
      backgroundColor: cameraOverlay ? const Color(0xEB101714) : Colors.white,
      elevation: 8,
      selectedLabelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.camera_alt_outlined),
          activeIcon: Icon(Icons.camera_alt),
          label: 'Deteksi',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu_book_outlined),
          activeIcon: Icon(Icons.menu_book),
          label: 'Kamus',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
      ],
    );
  }
}
