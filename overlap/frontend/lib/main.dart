import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';

void main() {
  runApp(const OverlapApp());
}

class OverlapApp extends StatelessWidget {
  const OverlapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OVERLAP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const LoginScreen(),
    );
  }
}
