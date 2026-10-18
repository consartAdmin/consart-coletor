import 'package:flutter/material.dart';

import 'api_service.dart';
import 'home_page.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.instance.load();
  runApp(const ColetorApp());
}

class ColetorApp extends StatelessWidget {
  const ColetorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F4E8C));
    return MaterialApp(
      title: 'CONSART Coletor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4E8C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: ApiService.instance.isLoggedIn
          ? const HomePage()
          : const LoginPage(),
    );
  }
}
