import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../widgets/auth_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nicknameController = TextEditingController();
  int? _birthYear;
  int? _birthMonth;
  int? _birthDay;
  String? _gender;
  bool _agreedToRequiredTerms = false;
  bool _isPasswordVisible = false;
  bool _isPasswordConfirmVisible = false;

  List<int> get _years =>
      List.generate(100, (index) => DateTime.now().year - index);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _signup() {
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
    if (_passwordConfirmController.text.isEmpty) {
      _showMessage('비밀번호 확인을 입력해 주세요.');
      return;
    }
    if (_passwordController.text != _passwordConfirmController.text) {
      _showMessage('비밀번호가 일치하지 않아요.');
      return;
    }
    if (_nicknameController.text.trim().isEmpty) {
      _showMessage('닉네임을 입력해 주세요.');
      return;
    }
    if (_birthYear == null) {
      _showMessage('출생연도를 선택해 주세요.');
      return;
    }
    if (_birthMonth == null || _birthDay == null) {
      _showMessage('생일 월과 일을 선택해 주세요.');
      return;
    }
    if (_gender == null) {
      _showMessage('성별을 선택해 주세요.');
      return;
    }
    if (!_agreedToRequiredTerms) {
      _showMessage('필수 약관에 동의해 주세요.');
      return;
    }
    Navigator.pop(context, email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: '뒤로가기',
        ),
        title: const Text(
          '회원가입',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'OVERLAP과 함께\n새로운 장소를 기록해요.',
                style: TextStyle(
                  color: AppColors.deepNavy,
                  fontSize: 25,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                '필수 정보만 입력하면 바로 시작할 수 있어요.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthTextField(
                        controller: _emailController,
                        label: '이메일 *',
                        hintText: 'example@overlap.com',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthTextField(
                        controller: _passwordController,
                        label: '비밀번호 *',
                        hintText: '비밀번호를 입력해 주세요',
                        obscureText: !_isPasswordVisible,
                        suffixIcon: _visibilityButton(
                          isVisible: _isPasswordVisible,
                          onTap: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthTextField(
                        controller: _passwordConfirmController,
                        label: '비밀번호 확인 *',
                        hintText: '비밀번호를 한 번 더 입력해 주세요',
                        obscureText: !_isPasswordConfirmVisible,
                        suffixIcon: _visibilityButton(
                          isVisible: _isPasswordConfirmVisible,
                          onTap: () => setState(
                            () => _isPasswordConfirmVisible =
                                !_isPasswordConfirmVisible,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AuthTextField(
                        controller: _nicknameController,
                        label: '닉네임 *',
                        hintText: '표시할 이름을 입력해 주세요',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _FieldLabel('출생연도 *'),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<int>(
                        initialValue: _birthYear,
                        hint: const Text('출생연도를 선택해 주세요'),
                        isExpanded: true,
                        items: [
                          for (final year in _years)
                            DropdownMenuItem(
                              value: year,
                              child: Text('$year년'),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _birthYear = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _FieldLabel('생일 *'),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _birthMonth,
                              hint: const Text('월 선택'),
                              isExpanded: true,
                              items: [
                                for (var month = 1; month <= 12; month++)
                                  DropdownMenuItem(
                                    value: month,
                                    child: Text(
                                      '${month.toString().padLeft(2, '0')}월',
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _birthMonth = value),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _birthDay,
                              hint: const Text('일 선택'),
                              isExpanded: true,
                              items: [
                                for (var day = 1; day <= 31; day++)
                                  DropdownMenuItem(
                                    value: day,
                                    child: Text(
                                      '${day.toString().padLeft(2, '0')}일',
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _birthDay = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _FieldLabel('성별 *'),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        hint: const Text('성별 선택'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'female', child: Text('여성')),
                          DropdownMenuItem(value: 'male', child: Text('남성')),
                        ],
                        onChanged: (value) => setState(() => _gender = value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: CheckboxListTile(
                  value: _agreedToRequiredTerms,
                  onChanged: (value) =>
                      setState(() => _agreedToRequiredTerms = value ?? false),
                  activeColor: AppColors.coral,
                  title: const Text(
                    '필수 약관에 동의합니다.',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(onPressed: _signup, child: const Text('회원가입')),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '현재는 mock 회원가입 화면입니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visibilityButton({
    required bool isVisible,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        isVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      tooltip: isVisible ? '비밀번호 숨기기' : '비밀번호 보기',
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.deepNavy,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
