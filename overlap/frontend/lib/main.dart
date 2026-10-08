import 'dart:async';

import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(ApiClient.checkHealth());
  runApp(const OverlapApp());
}

class OverlapApp extends StatefulWidget {
  const OverlapApp({super.key});

  @override
  State<OverlapApp> createState() => _OverlapAppState();
}

class _OverlapAppState extends State<OverlapApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    ApiClient.sessionRevision.addListener(_redirectExpiredSessionToLogin);
  }

  @override
  void dispose() {
    ApiClient.sessionRevision.removeListener(_redirectExpiredSessionToLogin);
    super.dispose();
  }

  void _redirectExpiredSessionToLogin() {
    if (!ApiClient.sessionExpired) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ApiClient.sessionExpired) return;
      _navigatorKey.currentState?.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(sessionExpired: true),
        ),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'OVERLAP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const LoginScreen(),
    );
  }
}
