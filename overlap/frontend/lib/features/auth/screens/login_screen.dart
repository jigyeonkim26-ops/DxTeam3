import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../home/screens/app_shell_screen.dart';
import '../widgets/auth_text_field.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _login() async {
    if (_isSubmitting) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('이메일을 입력해 주세요.');
      return;
    }
    if (!_isValidEmail(email)) {
      _showMessage('이메일 형식을 확인해 주세요.');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showMessage('비밀번호를 입력해 주세요.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ApiClient.login(email: email, password: _passwordController.text);
      await ApiClient.me();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShellScreen()),
      );
    } on ApiException catch (error) {
      ApiClient.clearSession();
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openSignup() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const SignupScreen()),
    );
    if (!mounted || email == null) return;
    _emailController.text = email;
    _showMessage('회원가입이 완료되었어요. 로그인해 주세요.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'OVERLAP',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.deepNavy,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '장소에 겹쳐진 우리의 순간을 기록해요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthTextField(
                        controller: _emailController,
                        label: '이메일',
                        hintText: 'example@overlap.com',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthTextField(
                        controller: _passwordController,
                        label: '비밀번호',
                        hintText: '비밀번호를 입력해 주세요',
                        textInputAction: TextInputAction.done,
                        obscureText: !_isPasswordVisible,
                        onSubmitted: (_) => _login(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          tooltip: _isPasswordVisible ? '비밀번호 숨기기' : '비밀번호 보기',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _login,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('로그인'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () =>
                        _showMessage('이메일 찾기는 백엔드 연동 후 제공될 예정이에요.'),
                    child: const Text('이메일 찾기'),
                  ),
                  const SizedBox(
                    height: 18,
                    child: VerticalDivider(color: AppColors.divider),
                  ),
                  TextButton(
                    onPressed: () =>
                        _showMessage('비밀번호 찾기는 백엔드 연동 후 제공될 예정이에요.'),
                    child: const Text('비밀번호 찾기'),
                  ),
                ],
              ),
              TextButton(
                onPressed: _openSignup,
                child: const Text('계정이 없나요? 회원가입'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
