import 'package:flutter/material.dart';
import 'package:mathmate/models/library_question.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/profile_radar_chart.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/pages/exam_creation_page.dart';
import 'package:mathmate/pages/question_solver_page.dart';
import 'package:mathmate/services/library_question_service.dart';

/// 练习页面 —— 根据学习画像从服务器题库推荐难度适配的题目
class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final AbilityScoreService _abilityService = AbilityScoreService();
  final LibraryQuestionService _questionService = LibraryQuestionService();

  /// 当前推荐的题目列表
  List<LibraryQuestion> _questions = <LibraryQuestion>[];

  /// 推荐元数据
  Map<String, DimensionRecommendDetail> _details = <String, DimensionRecommendDetail>{};

  /// 加载状态
  bool _isLoading = false;

  /// 错误信息
  String? _errorMessage;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _abilityService.addListener(_onAbilityChanged);
    _loadRecommendations();
  }

  @override
  void dispose() {
    _abilityService.removeListener(_onAbilityChanged);
    super.dispose();
  }

  void _onAbilityChanged() {
    if (mounted) setState(() {});
  }

  /// 从服务器加载推荐题目
  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final UserRadarProfile profile = _abilityService.computedProfile;
      final RecommendationResult result = await _questionService.recommend(
        profile: profile,
        targetCount: 10,
      );

      if (!mounted) return;
      setState(() {
        _questions = result.questions;
        _details = result.details;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '加载题目失败，请检查网络后重试';
      });
    }
  }

  /// 换一批
  void _onRefresh() {
    _questionService.resetShown();
    _loadRecommendations();
  }

  @override
  Widget build(BuildContext context) {
    final UserRadarProfile profile = _abilityService.computedProfile;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 400;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                // 顶部区域：文字 + 六维雷达图
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildHeaderText(),
                            const SizedBox(height: 12),
                            _buildRadarChart(profile),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            Expanded(child: _buildHeaderText()),
                            const SizedBox(width: 8),
                            _buildRadarChart(profile),
                          ],
                        ),
                ),

                // 换一批按钮 + 状态
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: <Widget>[
                      if (_isLoading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Text(
                          '共 ${_questions.length} 题',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _isLoading ? null : _onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('换一批'),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 题目列表 / 加载中 / 错误 / 空状态
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),

            // 右下角悬浮"自由组卷"按钮
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExamCreationPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.post_add_rounded),
                label: const Text('自由组卷'),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在从题库获取推荐题目...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadRecommendations,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.assignment_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Text('暂无推荐题目', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _onRefresh,
              child: const Text('刷新'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _questions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _QuestionCard(
          question: _questions[index],
          index: index,
          detail: _details[_questions[index].dimensionFromSection],
        );
      },
    );
  }

  /// 顶部提示文字 + 维度评分摘要
  Widget _buildHeaderText() {
    // 生成各维度能力值摘要
    final List<DimensionRecommendDetail> sorted = _details.values.toList()
      ..sort((a, b) => a.score.compareTo(b.score));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 6),
            const Text(
              '学习画像',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '根据你的学习画像，为您推荐以下难度适配的题目：',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: cs.onSurface.withValues(alpha: 0.75),
            height: 1.4,
          ),
        ),
        if (sorted.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 弱项提醒
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              ...sorted.take(2).map((d) => _buildDimChip(d, isWeak: true)),
            ],
          ),
        ],
      ],
    );
  }

  /// 维度评分小标签
  Widget _buildDimChip(DimensionRecommendDetail d, {bool isWeak = false}) {
    final double display = d.score * UserRadarProfile.displayMultiplier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isWeak
            ? Colors.orange.withValues(alpha: 0.12)
            : cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${d.dimension} ${display.toStringAsFixed(1)}分',
        style: TextStyle(
          fontSize: 11,
          color: isWeak ? Colors.orange.shade700 : cs.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 六维能力雷达图（小尺寸）
  Widget _buildRadarChart(UserRadarProfile profile) {
    return SizedBox(
      width: 220,
      height: 220,
      child: ProfileRadarChart(profile: profile),
    );
  }
}

/// 题目卡片组件（显示服务器题库真实题目）
class _QuestionCard extends StatelessWidget {
  final LibraryQuestion question;
  final int index;
  final DimensionRecommendDetail? detail;

  const _QuestionCard({
    required this.question,
    required this.index,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    // 难度星级（服务器难度 0~1 → 1~5 星）
    final int stars = (question.difficulty * 5).round().clamp(1, 5);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 题号 + 题型 + 难度星级
            Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    question.content,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                // 难度星星
                ...List<Widget>.generate(5, (i) {
                  return Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: i < stars ? Colors.amber : cs.outline,
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            // 选项（如有）
            if (question.options != null && question.options!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: question.options!.map((opt) {
                    return Text(
                      opt,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  }).toList(),
                ),
              ),
            // 知识点标签
            if (question.knowledgePoints.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: question.knowledgePoints.map((kp) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      kp,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),
            // 底部：来源 + 分类标签
            Row(
              children: <Widget>[
                if (question.sourceRef.isNotEmpty) ...[
                  Icon(Icons.menu_book_rounded, size: 14, color: cs.outline),
                  const SizedBox(width: 4),
                  Text(
                    question.sourceRef,
                    style: TextStyle(fontSize: 11, color: cs.outline),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    question.section,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 开始作答按钮（独立一行，全宽）
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => QuestionSolverPage(question: question),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('开始作答'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LibraryQuestion 扩展：根据 section 反查所属维度名
extension LibraryQuestionDimension on LibraryQuestion {
  String get dimensionFromSection {
    for (final MapEntry<String, List<String>> e
        in UserRadarProfile.dimensionTags.entries) {
      if (e.value.contains(section)) {
        return e.key;
      }
    }
    return '综合应用';
  }
}
