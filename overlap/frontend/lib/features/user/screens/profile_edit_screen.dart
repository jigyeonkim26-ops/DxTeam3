import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_transport.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/services/auth_api_service.dart';
import '../models/user_profile.dart';
import '../widgets/profile_photo_avatar.dart';

class ProfileEditResult {
  const ProfileEditResult({required this.profile, required this.photoChanged});

  final UserProfile profile;
  final bool photoChanged;
}

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.profile,
    this.photoRevision = 0,
  });

  final UserProfile profile;
  final int photoRevision;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameController;
  late final TextEditingController _birthDateController;
  late UserProfile _profile;
  late DateTime _birthDate;
  late String _gender;
  XFile? _selectedPhoto;
  bool _removePhoto = false;
  bool _isSaving = false;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _nicknameController = TextEditingController(text: _profile.nickname);
    _birthDate = _profile.birthDate;
    _birthDateController = TextEditingController(text: _formatDate(_birthDate));
    _gender = _profile.gender;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickBirthDate() async {
    if (_isSaving) return;
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthDate.isAfter(today) ? today : _birthDate,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _birthDate = selected;
      _birthDateController.text = _formatDate(selected);
    });
  }

  Future<void> _pickPhoto() async {
    if (_isSaving || _isLoggingOut) return;
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    setState(() {
      _selectedPhoto = photo;
      _removePhoto = false;
    });
  }

  void _markPhotoForRemoval() {
    if (_isSaving || _isLoggingOut) return;
    setState(() {
      _selectedPhoto = null;
      _removePhoto = true;
    });
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _isLoggingOut) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nickname = _nicknameController.text.trim();
    final birthDate = _formatDate(_birthDate);
    final nicknameChanged = nickname != _profile.nickname;
    final birthDateChanged = birthDate != _profile.birthDateText;
    final genderChanged = _gender != _profile.gender;
    final photoChanged = _selectedPhoto != null || _removePhoto;
    if (!nicknameChanged &&
        !birthDateChanged &&
        !genderChanged &&
        !photoChanged) {
      _showMessage('변경된 프로필 정보가 없습니다.');
      return;
    }

    setState(() => _isSaving = true);
    var updated = _profile;
    var detailsSaved = false;
    try {
      if (nicknameChanged || birthDateChanged || genderChanged) {
        updated = await AuthApiService.updateCurrentUser(
          nickname: nicknameChanged ? nickname : null,
          birthDate: birthDateChanged ? birthDate : null,
          gender: genderChanged ? _gender : null,
        );
        detailsSaved = true;
      }
      if (_selectedPhoto != null) {
        await AuthApiService.uploadProfilePhoto(_selectedPhoto!);
      } else if (_removePhoto) {
        await AuthApiService.deleteProfilePhoto();
      }
      if (!mounted) return;
      Navigator.of(context)
          .pop(ProfileEditResult(profile: updated, photoChanged: photoChanged));
    } on ApiException catch (error) {
      if (mounted) {
        if (detailsSaved) {
          setState(() => _profile = updated);
          _showMessage('기본 정보는 저장됐지만 사진 저장에 실패했습니다. 다시 시도해 주세요.');
        } else {
          _showMessage(error.message);
        }
      }
    } catch (_) {
      if (mounted) _showMessage('프로필 정보를 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    if (shouldLogout != true || !mounted || _isLoggingOut || _isSaving) return;

    setState(() => _isLoggingOut = true);
    try {
      await AuthApiService.logout();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
      return;
    } catch (_) {
      if (mounted) _showMessage('로그아웃 요청을 처리하지 못했습니다.');
      return;
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: _isSaving ? null : () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: '뒤로가기',
        ),
        title: const Text('프로필', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: _isSaving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            children: [
              _ProfileHeader(
                nickname: _nicknameController.text,
                localImagePath: _selectedPhoto?.path,
                showRemotePhoto: !_removePhoto,
                photoRevision: widget.photoRevision,
                onPhotoTap: _pickPhoto,
                onPhotoRemove: _markPhotoForRemoval,
              ),
              const SizedBox(height: AppSpacing.lg),
              Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('이메일'),
                        const SizedBox(height: AppSpacing.xs),
                        _ReadOnlyProfileField(
                          value: profile.email,
                          icon: Icons.lock_outline,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('닉네임'),
                        const SizedBox(height: AppSpacing.xs),
                        TextFormField(
                          controller: _nicknameController,
                          maxLength: 50,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: '닉네임을 입력해 주세요',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '닉네임을 입력해 주세요.';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('생년월일'),
                        const SizedBox(height: AppSpacing.xs),
                        TextFormField(
                          controller: _birthDateController,
                          readOnly: true,
                          onTap: _pickBirthDate,
                          decoration: const InputDecoration(
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _FieldLabel('성별'),
                        const SizedBox(height: AppSpacing.xs),
                        DropdownButtonFormField<String>(
                          initialValue: _gender,
                          decoration: const InputDecoration(),
                          items: const [
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('여성'),
                            ),
                            DropdownMenuItem(value: 'male', child: Text('남성')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _gender = value);
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: _saveProfile,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_isSaving ? '저장 중...' : '저장'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: AppSpacing.xl, color: AppColors.divider),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: const Key('profile-logout'),
                  onPressed: _isLoggingOut || _isSaving ? null : _confirmLogout,
                  icon: _isLoggingOut
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.logout_rounded),
                  label: const Text('로그아웃'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.coral,
                    side: const BorderSide(color: AppColors.coral),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.nickname,
    required this.localImagePath,
    required this.showRemotePhoto,
    required this.photoRevision,
    required this.onPhotoTap,
    required this.onPhotoRemove,
  });

  final String nickname;
  final String? localImagePath;
  final bool showRemotePhoto;
  final int photoRevision;
  final VoidCallback onPhotoTap;
  final VoidCallback onPhotoRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: '프로필 사진 변경',
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPhotoTap,
              customBorder: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfilePhotoAvatar(
                    radius: 36,
                    iconSize: 38,
                    localImagePath: localImagePath,
                    showRemote: showRemotePhoto,
                    revision: photoRevision,
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
                        Icons.photo_camera_outlined,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onPhotoRemove,
          icon: const Icon(Icons.delete_outline, size: 17),
          label: const Text('사진 삭제'),
          style: TextButton.styleFrom(foregroundColor: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          nickname,
          style: const TextStyle(
            color: AppColors.deepNavy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyProfileField extends StatelessWidget {
  const _ReadOnlyProfileField({required this.value, this.icon});

  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        suffixIcon: icon == null ? null : Icon(icon, size: 20),
      ),
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
