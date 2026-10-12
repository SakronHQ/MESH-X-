import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/home_navigation_screen.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: MeshXApp(),
    ),
  );
}

class MeshXApp extends StatelessWidget {
  const MeshXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MESH-X',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeNavigationScreen(),
    );
  }
}
