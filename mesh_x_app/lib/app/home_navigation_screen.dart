import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../features/chat/presentation/chat_placeholder_screen.dart';
import '../features/device/presentation/device_scanner_screen.dart';

class HomeNavigationScreen extends StatefulWidget {
  const HomeNavigationScreen({super.key});

  @override
  State<HomeNavigationScreen> createState() => _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends State<HomeNavigationScreen> {
  int _currentIndex = 1; // Default to Hardware tab on first launch

  final List<Widget> _screens = const [
    ChatPlaceholderScreen(),
    DeviceScannerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined),
              activeIcon: Icon(Icons.forum),
              label: 'Messages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.router_outlined),
              activeIcon: Icon(Icons.router),
              label: 'Hardware Node',
            ),
          ],
        ),
      ),
    );
  }
}
