import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../auth/screens/login_screen.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.initialProfileImagePath});

  final String? initialProfileImagePath;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class ProfileEditResult {
  const ProfileEditResult({required this.profileImagePath});

  final String? profileImagePath;
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _emailController = TextEditingController(text: 'example@overlap.com');
  final _nicknameController = TextEditingController(text: '서연');
  int? _birthYear = 1997;
  int? _birthMonth = 4;
  int? _birthDay = 18;
  String? _gender = 'female';
  late String? _profileImagePath;

  List<int> get _years =>
      List.generate(100, (index) => DateTime.now().year - index);

  @override
  void initState() {
    super.initState();
    _profileImagePath = widget.initialProfileImagePath;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _saveProfile() {
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
    // 향후 프로필 사진 업로드 및 사용자 정보 저장 API를 이 위치에 연결합니다.
    Navigator.pop(
      context,
      ProfileEditResult(profileImagePath: _profileImagePath),
    );
  }

  Future<void> _showPhotoActionSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  '프로필 사진 변경',
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('갤러리에서 사진 선택'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('기본 이미지로 변경'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() => _profileImagePath = null);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('취소'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (!mounted || image == null) return;
      setState(() => _profileImagePath = image.path);
    } catch (_) {
      if (mounted) _showMessage('사진을 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('로그아웃할까요?'),
        content: const Text('현재 계정에서 로그아웃합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !mounted) return;

    // 향후 JWT/refresh token 삭제 및 logout API 호출을 이 위치에 연결합니다.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
          '프로필 수정',
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
              _ProfileHeader(
                profileImagePath: _profileImagePath,
                onTap: _showPhotoActionSheet,
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FieldLabel('이메일'),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _emailController,
                        readOnly: true,
                        maxLines: 1,
                        decoration: const InputDecoration(
                          suffixIcon: Icon(Icons.lock_outline, size: 20),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _FieldLabel('닉네임 *'),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _nicknameController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          hintText: '표시할 이름을 입력해 주세요',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _FieldLabel('출생연도 *'),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<int>(
                        initialValue: _birthYear,
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
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _saveProfile,
                child: const Text('저장하기'),
              ),
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('로그아웃'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.coral,
                  side: const BorderSide(color: AppColors.coral),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '현재는 mock 프로필 수정 화면입니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profileImagePath, required this.onTap});

  final String? profileImagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.softMint,
                  foregroundColor: AppColors.deepNavy,
                  backgroundImage: profileImagePath == null
                      ? null
                      : FileImage(File(profileImagePath!)),
                  child: profileImagePath == null
                      ? const Icon(Icons.person, size: 38)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: AppColors.coral,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          '서연',
          style: TextStyle(
            color: AppColors.deepNavy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
