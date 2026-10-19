import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_transport.dart';
import '../../home/screens/app_shell_screen.dart';
import '../services/auth_api_service.dart';
import 'login_screen.dart';

class AuthBootstrapScreen extends StatefulWidget {
  const AuthBootstrapScreen({super.key});

  @override
  State<AuthBootstrapScreen> createState() => _AuthBootstrapScreenState();
}

class _AuthBootstrapScreenState extends State<AuthBootstrapScreen> {
  var _loading = true;
  var _restored = false;
  String? _temporaryError;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _temporaryError = null;
    });
    try {
      final restored = await AuthApiService.restoreSession();
      if (!mounted) return;
      setState(() {
        _restored = restored;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _temporaryError = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _temporaryError = '로그인 상태를 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_temporaryError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 16),
                Text(_temporaryError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
                TextButton(
                  onPressed: () async {
                    await ApiClient.clearPersistedRefreshToken();
                    ApiTransport.clearAccessToken();
                    if (mounted) setState(() => _temporaryError = null);
                  },
                  child: const Text('로그인 화면으로 이동'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _restored ? const AppShellScreen() : const LoginScreen();
  }
}
