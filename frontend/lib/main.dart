import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://uqamuaavlrkloamdtuek.supabase.co',
     publishableKey: 'sb_publishable_4miGpwXtOvExee833rxREA__auly_gI',
  );

  runApp(const AssistantVetApp());
}

class AssistantVetApp extends StatelessWidget {
  const AssistantVetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Assistant Vet',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: const Color(0xFFF4F8F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0AA7A0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FBFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFD8E5E5),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFFD8E5E5),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFF0AA7A0),
              width: 1.5,
            ),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}