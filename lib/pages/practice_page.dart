import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/data/history_repository.dart';
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

  /// 当前年级（用于维度→section 匹配）
  int? _grade;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _abilityService.addListener(_onAbilityChanged);
    // [摆拍] 启用演示模式：自评全 6.00 分 + 快速成长 λ
    // _abilityService.enableDemoMode();
    _loadGradeAndRecommend();
  }

  Future<void> _loadGradeAndRecommend() async {
    final int? grade;
    if (kIsWeb) {
      // Web 端从 HistoryRepository 获取（内部走 SharedPreferences）
      grade = await HistoryRepository.instance.getGradeLevel();
    } else {
      grade = await HistoryRepository.instance.getGradeLevel();
    }
    if (mounted) {
      setState(() => _grade = grade);
    }
    _abilityService.setGrade(grade);
    await _loadRecommendations();
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
        grade: _grade,
        targetCount: 10,
      );

      if (!mounted) return;

      // ====== [摆拍] 演示题目 ======
      // const LibraryQuestion demoBinomial = LibraryQuestion(
      //   id: 'demo_binomial_2022tj',
      //   section: '计数原理',
      //   type: '单选题',
      //   content: r'在 $(\sqrt{x} + \frac{3}{x^2})^5$ 的展开式中，常数项是',
      //   options: ['A. 5', 'B. 10', 'C. 15', 'D. 20'],
      //   answer: 'C',
      //   solution: r'由二项式定理，通项 $$T_{r+1} = C_5^r \cdot (\sqrt{x})^{5-r} \cdot \left(\frac{3}{x^2}\right)^r = C_5^r \cdot 3^r \cdot x^{\frac{5-r}{2}-2r}$$'
      //       '\n\n'
      //       r'令 $\frac{5-r}{2} - 2r = 0$，得 $5-r-4r=0$，即 $r=1$。'
      //       '\n\n'
      //       r'故常数项为 $T_2 = C_5^1 \cdot 3^1 = 5 \times 3 = 15$，选 C。',
      //   difficulty: 0.6,
      //   knowledgePoints: ['二项式定理', '常数项', '计数原理'],
      //   sourceRef: '2022天津卷',
      // );
      // const LibraryQuestion demoProbability = LibraryQuestion(
      //   id: 'demo_probability_5choose3',
      //   section: '计数原理',
      //   type: '填空题',
      //   content: r'从甲、乙等5名同学中随机选3名参加社区服务工作，则甲、乙都入选的概率为',
      //   answer: '3/10',
      //   solution: r'从5人中选3人，总选法为 $C_5^3 = 10$ 种。'
      //       '\n\n'
      //       r'甲、乙都入选时，只需再从剩余3人中选1人，选法为 $C_3^1 = 3$ 种。'
      //       '\n\n'
      //       r'故概率为 $\frac{3}{10}$。',
      //   difficulty: 0.5,
      //   knowledgePoints: ['古典概型', '组合计数', '计数原理'],
      //   sourceRef: '2022新课标卷',
      // );
      // final List<LibraryQuestion> questions = [demoBinomial, demoProbability, ...result.questions];
      // ====== [摆拍] 演示题目 END ======

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
          grade: _grade,
          detail: _details[_questions[index].dimensionFromSectionFor(_grade)],
          allQuestions: _questions,
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

/// 题目卡片组件（显示服务器题库真实题目，LaTeX 公式渲染）
class _QuestionCard extends StatelessWidget {
  final LibraryQuestion question;
  final int index;
  final int? grade;
  final DimensionRecommendDetail? detail;
  /// 全部推荐题目列表，传入 QuestionSolverPage 用于"下一题"跳转
  final List<LibraryQuestion> allQuestions;

  const _QuestionCard({
    required this.question,
    required this.index,
    this.grade,
    this.detail,
    this.allQuestions = const [],
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
            // 题号 + 题目内容（LaTeX 渲染） + 难度星级
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  child: ClipRect(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 48),
                      child: _buildLatexContent(
                        question.content,
                        cs,
                        fontSize: 14,
                      ),
                    ),
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
            // 选项（如有），label 用纯文本，内容走 LaTeX
            if (question.options != null && question.options!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: question.options!.map((opt) {
                    // 拆分 "A. content" → label "A." + content
                    final int dotIdx = opt.indexOf('.');
                    final String prefix = dotIdx >= 0 && dotIdx <= 2
                        ? '${opt.substring(0, dotIdx + 1)} '
                        : '';
                    final String body = dotIdx >= 0 && dotIdx <= 2
                        ? opt.substring(dotIdx + 1).trim()
                        : opt;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (prefix.isNotEmpty)
                          Text(
                            prefix,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        Flexible(
                          child: _buildLatexContent(body, cs, fontSize: 12),
                        ),
                      ],
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
                      builder: (_) => QuestionSolverPage(
                        question: question,
                        allQuestions: allQuestions,
                        currentIndex: index,
                      ),
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

// ---------------------------------------------------------------------------
// 内联 LaTeX 渲染辅助
// ---------------------------------------------------------------------------

/// 渲染混合普通文本 + $...$ 内联公式 + $$...$$ 块级公式的文本
Widget _buildLatexContent(String text, ColorScheme cs, {double fontSize = 14}) {
  if (!text.contains(r'$')) {
    // 纯文本，但可能包含不带 $ 的 LaTeX 命令，尝试用 Math.tex 渲染
    if (_containsLatexCommands(text)) {
      return Math.tex(
        text,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
        onErrorFallback: (err) =>
            Text(text, style: TextStyle(fontSize: fontSize, color: cs.onSurface)),
      );
    }
    return Text(text, style: TextStyle(fontSize: fontSize, color: cs.onSurface));
  }

  // 匹配 $$...$$ 块级公式（单行情况下）
  if (text.startsWith(r'$$') && text.endsWith(r'$$') && text.length > 4) {
    final formula = text.substring(2, text.length - 2).trim();
    return Math.tex(
      formula,
      mathStyle: MathStyle.display,
      textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
      onErrorFallback: (err) =>
          Text(formula, style: TextStyle(fontSize: fontSize, color: cs.onSurface)),
    );
  }

  // 内联 $...$ 混合解析
  final List<InlineSpan> spans = <InlineSpan>[];
  int i = 0;
  while (i < text.length) {
    if (text[i] == r'$') {
      final end = text.indexOf(r'$', i + 1);
      if (end != -1) {
        final formula = text.substring(i + 1, end);
        if (formula.trim().isNotEmpty) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              formula,
              mathStyle: MathStyle.text,
              textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
              onErrorFallback: (err) =>
                  Text(formula, style: TextStyle(fontSize: fontSize, color: cs.onSurface)),
            ),
          ));
        }
        i = end + 1;
        continue;
      }
    }
    // 普通文本，累积到下一个 $
    final nextDollar = text.indexOf(r'$', i);
    final String plainText = nextDollar == -1 ? text.substring(i) : text.substring(i, nextDollar);
    if (plainText.isNotEmpty) {
      spans.add(TextSpan(
        text: plainText,
        style: TextStyle(fontSize: fontSize, color: cs.onSurface),
      ));
    }
    if (nextDollar == -1) break;
    i = nextDollar;
  }

  return Text.rich(
    TextSpan(children: spans),
    maxLines: fontSize <= 13 ? 2 : null,
    overflow: fontSize <= 13 ? TextOverflow.ellipsis : null,
  );
}

/// 检测文本中是否包含 LaTeX 命令（\frac, \sqrt, \sum 等）
bool _containsLatexCommands(String text) {
  return RegExp(r'\\[a-zA-Z]+').hasMatch(text);
}

/// LibraryQuestion 扩展：根据 section 反查所属维度名（需传入年级以匹配正确维度体系）
extension LibraryQuestionDimension on LibraryQuestion {
  String dimensionFromSectionFor(int? grade) {
    final Map<String, List<String>> tags = UserRadarProfile.dimensionTagsFor(grade);
    for (final MapEntry<String, List<String>> e in tags.entries) {
      if (e.value.contains(section)) {
        return e.key;
      }
    }
    return '综合应用';
  }
}
