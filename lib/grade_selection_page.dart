import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/main.dart';
import 'package:mathmate/pages/ability_assessment_page.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/tutorial_page.dart';
import 'package:mathmate/theme/grade_ui_profile.dart';

class GradeSelectionPage extends StatefulWidget {
  final bool isFromSettings;

  const GradeSelectionPage({super.key, this.isFromSettings = false});

  @override
  State<GradeSelectionPage> createState() => _GradeSelectionPageState();
}

class _GradeSelectionPageState extends State<GradeSelectionPage> {
  int? _selectedGrade;

  static const Map<String, List<Map<String, dynamic>>> _gradeData =
      <String, List<Map<String, dynamic>>>{
        '小学': <Map<String, dynamic>>[
          <String, dynamic>{'label': '一年级', 'value': 1},
          <String, dynamic>{'label': '二年级', 'value': 2},
          <String, dynamic>{'label': '三年级', 'value': 3},
          <String, dynamic>{'label': '四年级', 'value': 4},
          <String, dynamic>{'label': '五年级', 'value': 5},
          <String, dynamic>{'label': '六年级', 'value': 6},
        ],
        '初中': <Map<String, dynamic>>[
          <String, dynamic>{'label': '初一', 'value': 7},
          <String, dynamic>{'label': '初二', 'value': 8},
          <String, dynamic>{'label': '初三', 'value': 9},
        ],
        '高中': <Map<String, dynamic>>[
          <String, dynamic>{'label': '高一', 'value': 10},
          <String, dynamic>{'label': '高二', 'value': 11},
          <String, dynamic>{'label': '高三', 'value': 12},
        ],
        '大学': <Map<String, dynamic>>[
          <String, dynamic>{'label': '大一', 'value': 13},
          <String, dynamic>{'label': '大二', 'value': 14},
          <String, dynamic>{'label': '大三', 'value': 15},
          <String, dynamic>{'label': '大四', 'value': 16},
          <String, dynamic>{'label': '研究生', 'value': 17},
        ],
      };

  @override
  void initState() {
    super.initState();
    _loadCurrentGrade();
  }

  Future<void> _loadCurrentGrade() async {
    final int? grade = await _getCurrentGrade();
    if (mounted && grade != null) {
      setState(() {
        _selectedGrade = grade;
      });
    }
  }

  Future<int?> _getCurrentGrade() async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getInt('web_grade');
    }
    return HistoryRepository.instance.getGradeLevel();
  }

  Future<void> _saveGrade(int grade) async {
    if (kIsWeb) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('web_grade', grade);
    } else {
      await HistoryRepository.instance.setGradeLevel(grade);
    }
    // 通知能力评分服务切换维度体系
    AbilityScoreService().setGrade(grade);
  }

  String _getGradeDisplayText() {
    if (_selectedGrade == null) return '未选择';
    for (final String category in _gradeData.keys) {
      for (final Map<String, dynamic> grade in _gradeData[category]!) {
        if (grade['value'] == _selectedGrade) {
          return '$category${grade['label']}';
        }
      }
    }
    return '未选择';
  }

  @override
  Widget build(BuildContext context) {
    final GradeUiProfile gradeUi = GradeUiProfile.forGrade(_selectedGrade);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: gradeUi.surfaceTint,
      appBar: AppBar(
        title: const Text('选择年级'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: gradeUi.primary,
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              final NavigatorState navigator = Navigator.of(context);
              await HistoryRepository.instance.setFirstLaunchComplete();
              if (mounted) {
                navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                  (Route<dynamic> route) => false,
                );
              }
            },
            child: Text(
              '跳过',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: gradeUi.primary,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GradeBackdrop(
              profile: gradeUi,
              imageAsset: 'assets/images/background-profile.png',
              veilStrength: 0.68,
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        '请选择您的年级',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '我们将为您推荐适合的学习内容',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                      if (_selectedGrade != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: gradeUi.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '当前选择：${_getGradeDisplayText()}',
                            style: TextStyle(
                              color: gradeUi.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ..._buildGradeCategories(),
                const SizedBox(height: 30),
                if (_selectedGrade != null)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        final NavigatorState navigator = Navigator.of(context);
                        await _saveGrade(_selectedGrade!);
                        if (!widget.isFromSettings) {
                          await HistoryRepository.instance
                              .setFirstLaunchComplete();
                        }
                        if (mounted) {
                          if (widget.isFromSettings) {
                            navigator.pop(_selectedGrade);
                          } else {
                            // 年级选择后 → 能力自评 → 新手引导
                            navigator.pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => AbilityAssessmentPage(
                                  nextPage: const TutorialPage(),
                                ),
                              ),
                              (Route<dynamic> route) => false,
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gradeUi.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        widget.isFromSettings ? '保存' : '开始使用',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGradeCategories() {
    final List<Widget> categories = <Widget>[];
    int index = 0;

    for (final String category in _gradeData.keys) {
      categories.add(_buildCategoryHeader(category));
      categories.add(const SizedBox(height: 12));
      categories.add(_buildGradeGrid(_gradeData[category]!));
      if (index < _gradeData.keys.length - 1) {
        categories.add(const SizedBox(height: 24));
      }
      index++;
    }

    return categories;
  }

  Widget _buildCategoryHeader(String title) {
    final GradeUiProfile gradeUi = GradeUiProfile.forGrade(_selectedGrade);
    IconData icon;
    switch (title) {
      case '小学':
        icon = Icons.school_outlined;
        break;
      case '初中':
        icon = Icons.account_balance_outlined;
        break;
      case '高中':
        icon = Icons.psychology_outlined;
        break;
      case '大学':
        icon = Icons.local_library_outlined;
        break;
      default:
        icon = Icons.book_outlined;
    }

    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: gradeUi.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: gradeUi.primary, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildGradeGrid(List<Map<String, dynamic>> grades) {
    final GradeUiProfile gradeUi = GradeUiProfile.forGrade(_selectedGrade);
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: grades.map((Map<String, dynamic> grade) {
        final bool isSelected = _selectedGrade == grade['value'];
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedGrade = grade['value'] as int;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? gradeUi.primary
                  : cs.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(
                gradeUi.cardRadius.clamp(10.0, 14.0).toDouble(),
              ),
              border: Border.all(
                color: isSelected ? gradeUi.primary : const Color(0xFFE0E0E0),
                width: 1.5,
              ),
              boxShadow: isSelected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: gradeUi.primary.withValues(alpha: 0.24),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              grade['label'] as String,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF5D6778),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
