import 'package:flutter/material.dart';
import 'package:mathmate/pages/exam_result_page.dart';
import 'package:mathmate/services/exam_api.dart';

/// 考试答题页 —— 从考试系统获取题目，逐题作答
class ExamTakingPage extends StatefulWidget {
  final ExamApi api;
  final String studentId;
  final String title;
  final int totalCount;
  final String? board;
  final double? difficultyMin;
  final double? difficultyMax;
  final List<String>? questionTypes;

  const ExamTakingPage({
    super.key,
    required this.api,
    required this.studentId,
    required this.title,
    required this.totalCount,
    this.board,
    this.difficultyMin,
    this.difficultyMax,
    this.questionTypes,
  });

  @override
  State<ExamTakingPage> createState() => _ExamTakingPageState();
}

class _ExamTakingPageState extends State<ExamTakingPage> {
  final Map<int, TextEditingController> _controllers = <int, TextEditingController>{};
  final Map<int, String> _choiceAnswers = <int, String>{};
  final Map<int, Map<String, dynamic>> _graded = <int, Map<String, dynamic>>{};

  bool _loading = true;
  bool _submitting = false;
  int? _examId;
  List<Map<String, dynamic>> _questions = <Map<String, dynamic>>[];
  String? _error;
  int _answeredCount = 0;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _createExam();
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createExam() async {
    try {
      final Map<String, dynamic> result = await widget.api.createExam(
        studentId: widget.studentId,
        title: widget.title,
        totalCount: widget.totalCount,
        board: widget.board,
        difficultyMin: widget.difficultyMin,
        difficultyMax: widget.difficultyMax,
        questionTypes: widget.questionTypes,
      );
      final List<dynamic> raw = result['questions'] as List<dynamic>;
      setState(() {
        _examId = result['exam_id'] as int;
        _questions = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submitQuestion(Map<String, dynamic> question) async {
    final int? examId = _examId;
    if (examId == null) return;

    final int questionId = question['id'] as int;
    final String type = question['question_type'] as String;
    final String answer = type == 'choice'
        ? _choiceAnswers[questionId] ?? ''
        : _controllers[questionId]?.text ?? '';

    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入或选择答案')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final Map<String, dynamic> result = await widget.api.submitAnswer(
        examId: examId,
        studentId: widget.studentId,
        questionId: questionId,
        studentAnswer: answer,
      );
      setState(() {
        _graded[questionId] = result;
        _answeredCount = _graded.length;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _finishExam() async {
    final int? examId = _examId;
    if (examId == null) return;

    // 确认提交
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认交卷'),
        content: Text('已作答 $_answeredCount / ${_questions.length} 题，确定交卷吗？'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('继续作答')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认交卷')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final Map<String, dynamic> result = await widget.api.finishExam(
        examId: examId,
        studentId: widget.studentId,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ExamResultPage(report: result),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('交卷失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: Text(widget.title), backgroundColor: cs.surface),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在组卷...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: Text(widget.title), backgroundColor: cs.surface),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 64, color: cs.error),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_error!, textAlign: TextAlign.center,
                    style: TextStyle(color: cs.error)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() { _error = null; _loading = true; });
                  _createExam();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: cs.surface,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _finishExam,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text('交卷 ($_answeredCount/${_questions.length})'),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _questions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final Map<String, dynamic> question = _questions[index];
          final int qid = question['id'] as int;
          return _ExamQuestionCard(
            index: index,
            question: question,
            controller: _controllers.putIfAbsent(qid, TextEditingController.new),
            choiceValue: _choiceAnswers[qid],
            graded: _graded[qid],
            submitting: _submitting,
            onChoiceChanged: (String value) {
              setState(() => _choiceAnswers[qid] = value);
            },
            onSubmit: () => _submitQuestion(question),
          );
        },
      ),
    );
  }
}

/// 考试题目卡片（每题独立提交）
class _ExamQuestionCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> question;
  final TextEditingController controller;
  final String? choiceValue;
  final Map<String, dynamic>? graded;
  final bool submitting;
  final ValueChanged<String> onChoiceChanged;
  final VoidCallback onSubmit;

  const _ExamQuestionCard({
    required this.index,
    required this.question,
    required this.controller,
    required this.choiceValue,
    required this.graded,
    required this.submitting,
    required this.onChoiceChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String type = question['question_type'] as String;
    final Map<String, dynamic>? options =
        question['options'] as Map<String, dynamic>?;
    final String? board = question['board'] as String?;
    final double difficulty =
        (question['difficulty'] as num?)?.toDouble() ?? 0.5;
    final bool isGraded = graded != null;
    final bool isCorrect = graded?['is_correct'] as bool? ?? false;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isGraded
              ? (isCorrect ? Colors.green.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.3))
              : cs.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 题号 + 标签
            Row(
              children: <Widget>[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isGraded
                        ? (isCorrect ? Colors.green : Colors.red).withValues(alpha: 0.12)
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isGraded
                          ? (isCorrect ? Colors.green : Colors.red)
                          : cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildTypeBadge(type),
                const SizedBox(width: 6),
                if (board != null) ...[
                  Text(board, style: TextStyle(fontSize: 11, color: cs.outline)),
                  const SizedBox(width: 6),
                ],
                ...List<Widget>.generate(
                  (difficulty * 5).round().clamp(1, 5),
                  (i) => const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                ),
                const Spacer(),
                if (isGraded)
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect ? Colors.green : Colors.red,
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // 题目内容
            Text(
              question['content'] as String? ?? '',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 12),

            // 选项 / 输入区
            if (type == 'choice' && options != null)
              ...options.entries.map((entry) {
                final bool selected = choiceValue == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: isGraded
                        ? null
                        : () => onChoiceChanged(entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.08)
                            : cs.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: selected ? cs.primary : cs.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entry.key}. ${entry.value}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              })
            else
              TextField(
                controller: controller,
                enabled: !isGraded,
                minLines: type == 'short_answer' ? 4 : 1,
                maxLines: type == 'short_answer' ? 8 : 1,
                decoration: InputDecoration(
                  hintText: type == 'short_answer' ? '输入解答过程...' : '输入答案...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            const SizedBox(height: 12),

            // 提交按钮 / 评分结果
            if (!isGraded)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('提交本题'),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCorrect
                      ? Colors.green.withValues(alpha: 0.06)
                      : Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          '得分：${graded!['score']}/${graded!['max_score']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isCorrect ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (graded!['feedback'] != null &&
                            (graded!['feedback'] as String).isNotEmpty)
                          Expanded(
                            child: Text(
                              graded!['feedback'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final String label;
    final Color color;
    switch (type) {
      case 'choice':
        label = '单选';
        color = Colors.blue;
        break;
      case 'blank':
        label = '填空';
        color = Colors.orange;
        break;
      case 'short_answer':
        label = '简答';
        color = Colors.purple;
        break;
      default:
        label = type;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
