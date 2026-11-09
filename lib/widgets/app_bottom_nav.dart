import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.enabled = true,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2864F0)),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      fontFamily: 'Roboto',
      useMaterial3: true,
    );
    return Theme(
      data: lightTheme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).colorScheme;
          return BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: enabled ? onSelected : null,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: colors.primary,
            unselectedItemColor: colors.onSurfaceVariant,
            backgroundColor: colors.surface,
            elevation: 0,
            iconSize: 24,
            selectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: _SelectedNavIcon(icon: Icons.home_outlined),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.center_focus_weak_rounded),
                activeIcon: _SelectedNavIcon(icon: Icons.center_focus_weak_rounded),
                label: 'Deteksi',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_outlined),
                activeIcon: _SelectedNavIcon(icon: Icons.menu_book_outlined),
                label: 'Kamus',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded),
                activeIcon: _SelectedNavIcon(icon: Icons.history_rounded),
                label: 'Riwayat',
              ),
            ],
          );
        },
      ),
    );
  }

}

class _SelectedNavIcon extends StatelessWidget {
  const _SelectedNavIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer, size: 24),
    );
  }
}
