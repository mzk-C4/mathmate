import 'package:flutter/material.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/wrong_book/presentation/wrong_question_book_page.dart';
import 'package:mathmate/wrong_book/services/wrong_question_repository.dart';

/// 考试成绩报告页 —— 展示总分、板块分析、错题回顾，并更新六维能力评分
class ExamResultPage extends StatefulWidget {
  final Map<String, dynamic> report;

  const ExamResultPage({super.key, required this.report});

  @override
  State<ExamResultPage> createState() => _ExamResultPageState();
}

class _ExamResultPageState extends State<ExamResultPage> {
  final AbilityScoreService _abilityService = AbilityScoreService();
  bool _scoreUpdated = false;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _updateAbilityScores();
    WrongQuestionRepository.instance.importReport(widget.report);
  }

  /// 根据考试报告的 board_analysis 更新六维能力评分
  void _updateAbilityScores() {
    if (_scoreUpdated) return;

    final List<dynamic> boardAnalysis =
        widget.report['board_analysis'] as List<dynamic>? ?? <dynamic>[];

    // 汇总每个维度的答题数据
    final Map<String, _BoardStats> dimStats = <String, _BoardStats>{};
    final Map<String, List<String>> dimensionTags =
        UserRadarProfile.dimensionTagsFor(_abilityService.currentGrade);
    final List<String> dimensionNames = _abilityService.currentDimensionNames;
    for (final MapEntry<String, List<String>> entry in dimensionTags.entries) {
      dimStats[entry.key] = _BoardStats();
    }

    for (final dynamic item in boardAnalysis) {
      final Map<String, dynamic> board = item as Map<String, dynamic>;
      final String boardName = board['board'] as String? ?? '';
      final int total = (board['total'] as num?)?.toInt() ?? 0;
      final int correct = (board['correct'] as num?)?.toInt() ?? 0;

      // 找到该 board 对应的维度
      for (final MapEntry<String, List<String>> entry
          in dimensionTags.entries) {
        if (entry.value.contains(boardName)) {
          dimStats[entry.key]!.total += total;
          dimStats[entry.key]!.correct += correct;
          break;
        }
      }
    }

    // 写入能力评分系统
    for (final MapEntry<String, _BoardStats> entry in dimStats.entries) {
      final _BoardStats stats = entry.value;
      if (stats.total <= 0) continue;

      final int dimIndex = dimensionNames.indexOf(entry.key);
      if (dimIndex < 0) continue;

      // 每次答题算一条记录（按正确率折算）
      for (int i = 0; i < stats.total; i++) {
        _abilityService.recordAnswer(
          dimensionIndex: dimIndex,
          isCorrect: i < stats.correct,
          difficulty: 3.0, // 考试难度默认为中等
        );
      }
    }

    _scoreUpdated = true;
  }

  @override
  Widget build(BuildContext context) {
    final double totalScore =
        (widget.report['total_score'] as num?)?.toDouble() ?? 0;
    final double maxScore =
        (widget.report['max_score'] as num?)?.toDouble() ?? 0;
    final double accuracy =
        (widget.report['accuracy'] as num?)?.toDouble() ?? 0;
    final List<dynamic> boardAnalysis =
        widget.report['board_analysis'] as List<dynamic>? ?? <dynamic>[];
    final List<dynamic> wrongQuestions =
        widget.report['wrong_questions'] as List<dynamic>? ?? <dynamic>[];
    final bool isPassed = accuracy >= 0.6;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('考试报告'), backgroundColor: cs.surface),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          // 总分卡片
          _buildScoreCard(totalScore, maxScore, accuracy, isPassed),
          const SizedBox(height: 24),

          // 板块分析
          const Text(
            '板块分析',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (boardAnalysis.isEmpty)
            Text('暂无板块数据', style: TextStyle(color: cs.onSurfaceVariant))
          else
            ...boardAnalysis.map(
              (item) => _buildBoardItem(item as Map<String, dynamic>),
            ),
          const SizedBox(height: 24),

          // 能力评分更新提示
          _buildScoreUpdateCard(),
          const SizedBox(height: 24),

          // 错题回顾
          const Text(
            '错题回顾',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (wrongQuestions.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.green,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    '全部正确，太棒了！',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else
            ...wrongQuestions.map(
              (item) => _buildWrongItem(item as Map<String, dynamic>),
            ),
          if (wrongQuestions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WrongQuestionBookPage(),
                  ),
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('查看智能错题本'),
              ),
            ),
          const SizedBox(height: 32),

          // 底部操作
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('回到首页'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildScoreCard(
    double total,
    double max,
    double accuracy,
    bool passed,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: passed
              ? const <Color>[Color(0xFF22B07D), Color(0xFF1E9E6C)]
              : const <Color>[Color(0xFFE67E22), Color(0xFFD35400)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Text(
            passed ? '考试通过' : '继续加油',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${total.toStringAsFixed(0)} / ${max.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '正确率 ${(accuracy * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardItem(Map<String, dynamic> board) {
    final String name = board['board'] as String? ?? '未分类';
    final int total = (board['total'] as num?)?.toInt() ?? 0;
    final int correct = (board['correct'] as num?)?.toInt() ?? 0;
    final double score = (board['score'] as num?)?.toDouble() ?? 0;
    final double max = (board['max_score'] as num?)?.toDouble() ?? 0;
    final double rate = total > 0 ? correct / total : 0;

    // 找到对应的能力维度
    String? dimension;
    for (final MapEntry<String, List<String>> e
        in UserRadarProfile.dimensionTags.entries) {
      if (e.value.contains(name)) {
        dimension = e.key;
        break;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (dimension != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '→ $dimension',
                          style: TextStyle(fontSize: 11, color: cs.primary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '正确 $correct/$total  得分 $score/$max',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            // 进度条
            SizedBox(
              width: 60,
              child: Column(
                children: <Widget>[
                  LinearProgressIndicator(
                    value: rate,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: cs.surfaceContainerHighest,
                    color: rate >= 0.6 ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(rate * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreUpdateCard() {
    final UserRadarProfile profile = _abilityService.computedProfile;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.trending_up_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '六维能力已更新',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '综合能力 ${(profile.scores.reduce((a, b) => a + b) / profile.scores.length * UserRadarProfile.displayMultiplier).toStringAsFixed(1)} 分',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWrongItem(Map<String, dynamic> item) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              item['content']?.toString() ?? '',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            _buildWrongRow('你的答案', item['student_answer']?.toString()),
            _buildWrongRow(
              '正确答案',
              item['standard_answer']?.toString(),
              isCorrect: true,
            ),
            if (item['explanation'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '解析：${item['explanation']}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            if (item['llm_feedback'] != null &&
                (item['llm_feedback'] as String).isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '💡 ${item['llm_feedback']}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWrongRow(String label, String? value, {bool isCorrect = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isCorrect ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardStats {
  int total = 0;
  int correct = 0;
}
