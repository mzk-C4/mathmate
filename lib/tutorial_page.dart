import 'package:flutter/material.dart';
import 'package:mathmate/main.dart';
import 'package:mathmate/data/history_repository.dart';

class TutorialPage extends StatefulWidget {
  final bool isFromSettings;

  const TutorialPage({super.key, this.isFromSettings = false});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  int _currentStep = 0;

  static const List<Map<String, String>> _tutorialContent = [
    {
      'icon': 'camera_alt',
      'title': '拍照搜题',
      'subtitle': '一拍即解',
      'content': '点击中央拍照按钮\n拍摄题目自动识别\n秒出答案和解题步骤',
      'action': '点击中央拍照按钮',
    },
    {
      'icon': 'smart_toy',
      'title': 'MathMate 助手',
      'subtitle': 'AI 答疑 · 图片解题',
      'content': '点击搜索框进入对话\n11 个 AI 模型可选（DeepSeek/Doubao/Qwen）\n支持上传图片自动识别解题',
      'action': '点击搜索框 → 进入 MathMate 助手',
    },
    {
      'icon': 'folder_special',
      'title': '学习资料库',
      'subtitle': 'AI 自动整理',
      'content': '点击底部「资料库」Tab\n上传课件 / 真题 / 板书\nAI 自动分类整理归档',
      'action': '点击底部「资料库」Tab',
    },
    {
      'icon': 'fitness_center',
      'title': '题库练习',
      'subtitle': '个性化推荐',
      'content': '点击底部「练习」Tab\n按能力推荐题目\n做题提升能力雷达图',
      'action': '点击底部「练习」Tab',
    },
    {
      'icon': 'edit_note',
      'title': '智能笔记',
      'subtitle': '手写 + PDF',
      'content': '点击底部「笔记」Tab\n支持打字、手写、PDF 导入\n随时随地记录',
      'action': '点击底部「笔记」Tab → 点击右下角「+」新建笔记',
    },
    {
      'icon': 'radar',
      'title': '能力雷达图',
      'subtitle': '六维评估',
      'content': '点击底部「我的」Tab\n完成能力自评\n练习后雷达图实时更新',
      'action': '点击底部「我的」Tab → 查看能力雷达图',
    },
  ];

  void _nextStep() {
    if (_currentStep < _tutorialContent.length - 1) {
      setState(() => _currentStep++);
    } else {
      _completeTutorial();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  void _skipTutorial() {
    _completeTutorial();
  }

  Future<void> _completeTutorial() async {
    await HistoryRepository.instance.setTutorialCompleted();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'camera_alt':
        return Icons.camera_alt_rounded;
      case 'smart_toy':
        return Icons.smart_toy_rounded;
      case 'folder_special':
        return Icons.folder_special_rounded;
      case 'fitness_center':
        return Icons.fitness_center_rounded;
      case 'edit_note':
        return Icons.edit_note_rounded;
      case 'radar':
        return Icons.radar_rounded;
      default:
        return Icons.star_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> content = _tutorialContent[_currentStep];
    final bool isLastStep = _currentStep == _tutorialContent.length - 1;
    final bool isFirstStep = _currentStep == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: <Widget>[
          TextButton(
            onPressed: _skipTutorial,
            child: const Text(
              '跳过',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3F51B5),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _tutorialContent.length,
                  (int index) => Container(
                    width: index == _currentStep ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: index == _currentStep
                          ? const Color(0xFF3F51B5)
                          : const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8EEFF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getIcon(content['icon']!),
                  size: 56,
                  color: const Color(0xFF3F51B5),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                content['title']!,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                content['subtitle']!,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  content['content']!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.8,
                    color: Color(0xFF3A3A4A),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.touch_app, color: Color(0xFF3F51B5), size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        content['action']!,
                        style: const TextStyle(
                          color: Color(0xFF3F51B5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  if (!isFirstStep)
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _previousStep,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3F51B5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: Color(0xFF3F51B5)),
                          ),
                          child: const Text(
                            '上一步',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  if (!isFirstStep) const SizedBox(width: 12),
                  Expanded(
                    flex: isFirstStep ? 1 : 1,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3F51B5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          isLastStep ? '完成教程' : '下一步',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}