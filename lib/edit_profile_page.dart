import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/models/user_profile.dart';
import 'package:mathmate/services/user_profile_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final UserProfileService _profileService = UserProfileService();
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nicknameCtrl;
  late TextEditingController _bioCtrl;
  String _grade = 'Math Explorer';
  String? _avatarPath;

  static const List<String> _grades = [
    'Math Explorer',
    '小学',
    '初中',
    '高中',
    '大学',
  ];

  static String _gradeIntToLabel(int? g) {
    if (g == null) return 'Math Explorer';
    if (g <= 6) return '小学';
    if (g <= 9) return '初中';
    if (g <= 12) return '高中';
    return '大学';
  }

  @override
  void initState() {
    super.initState();
    final p = _profileService.profile;
    _nicknameCtrl = TextEditingController(text: p.nickname);
    _bioCtrl = TextEditingController(text: p.bio);
    // 年级优先从 HistoryRepository 读取（与初始选择一致），回退到已保存的 profile
    HistoryRepository.instance.getGradeLevel().then((g) {
      if (mounted) setState(() => _grade = _gradeIntToLabel(g));
    });
    _grade = p.grade.isNotEmpty && p.grade != 'Math Explorer'
        ? p.grade
        : _grade; // 先用默认值，等异步加载完成更新
    _avatarPath = p.avatar.isNotEmpty ? p.avatar : null;
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑个人资料'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      backgroundColor: cs.surfaceContainerLowest,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Avatar
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primaryContainer,
                  image: _avatarPath != null && File(_avatarPath!).existsSync()
                      ? DecorationImage(image: FileImage(File(_avatarPath!)), fit: BoxFit.cover)
                      : null,
                ),
                child: _avatarPath == null || !File(_avatarPath!).existsSync()
                    ? Icon(Icons.person, size: 44, color: cs.primary)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _pickAvatar,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('更换头像'),
            ),
          ),
          const SizedBox(height: 20),
          // Nickname
          Text('昵称', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _nicknameCtrl,
            decoration: InputDecoration(
              hintText: '请输入昵称',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surface,
            ),
          ),
          const SizedBox(height: 20),
          // Grade
          Text('年级', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _grade,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surface,
            ),
            items: _grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _grade = v);
            },
          ),
          const SizedBox(height: 20),
          // Bio
          Text('个性签名', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextField(
            controller: _bioCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '写一句话介绍自己...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) setState(() => _avatarPath = file.path);
  }

  void _save() {
    _profileService.save(UserProfile(
      nickname: _nicknameCtrl.text.trim().isEmpty ? 'MathMate_User' : _nicknameCtrl.text.trim(),
      avatar: _avatarPath ?? '',
      grade: _grade,
      bio: _bioCtrl.text.trim(),
    ));
    if (mounted) Navigator.pop(context);
  }
}
