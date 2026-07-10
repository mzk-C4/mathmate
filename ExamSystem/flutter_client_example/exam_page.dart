import 'package:flutter/material.dart';

import 'exam_api.dart';
import 'result_page.dart';

class ExamTakingPage extends StatefulWidget {
  const ExamTakingPage({super.key, required this.api, required this.studentId});

  final ExamApi api;
  final String studentId;

  @override
  State<ExamTakingPage> createState() => _ExamTakingPageState();
}

class _ExamTakingPageState extends State<ExamTakingPage> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, String> _choiceAnswers = {};
  final Map<int, Map<String, dynamic>> _graded = {};

  bool _loading = true;
  bool _submitting = false;
  int? _examId;
  List<dynamic> _questions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _createExam();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _createExam() async {
    try {
      final result = await widget.api.createExam(
        studentId: widget.studentId,
        title: '解析几何测试',
        totalCount: 5,
        questionTypes: const ['choice', 'blank', 'short_answer'],
      );
      setState(() {
        _examId = result['exam_id'] as int;
        _questions = result['questions'] as List<dynamic>;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submitQuestion(Map<String, dynamic> question) async {
    final examId = _examId;
    if (examId == null) return;

    final questionId = question['id'] as int;
    final type = question['question_type'] as String;
    final answer = type == 'choice'
        ? _choiceAnswers[questionId] ?? ''
        : _controllers[questionId]?.text ?? '';

    setState(() => _submitting = true);
    try {
      final result = await widget.api.submitAnswer(
        examId: examId,
        studentId: widget.studentId,
        questionId: questionId,
        studentAnswer: answer,
      );
      setState(() => _graded[questionId] = result);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _finishExam() async {
    final examId = _examId;
    if (examId == null) return;

    final result = await widget.api.finishExam(
      examId: examId,
      studentId: widget.studentId,
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ExamResultPage(report: result)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('智能测试')),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('智能测试'),
        actions: [TextButton(onPressed: _finishExam, child: const Text('交卷'))],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _questions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final question = _questions[index] as Map<String, dynamic>;
          return _QuestionCard(
            index: index,
            question: question,
            controller: _controllers.putIfAbsent(
              question['id'] as int,
              TextEditingController.new,
            ),
            choiceValue: _choiceAnswers[question['id']],
            graded: _graded[question['id']],
            submitting: _submitting,
            onChoiceChanged: (value) {
              setState(() => _choiceAnswers[question['id'] as int] = value);
            },
            onSubmit: () => _submitQuestion(question),
          );
        },
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.controller,
    required this.choiceValue,
    required this.graded,
    required this.submitting,
    required this.onChoiceChanged,
    required this.onSubmit,
  });

  final int index;
  final Map<String, dynamic> question;
  final TextEditingController controller;
  final String? choiceValue;
  final Map<String, dynamic>? graded;
  final bool submitting;
  final ValueChanged<String> onChoiceChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final type = question['question_type'] as String;
    final options = question['options'] as Map<String, dynamic>?;
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${question['content']}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (type == 'choice' && options != null)
              ...options.entries.map((entry) {
                final selected = choiceValue == entry.key;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? theme.colorScheme.primary : null,
                  ),
                  title: Text('${entry.key}. ${entry.value}'),
                  onTap: () => onChoiceChanged(entry.key),
                );
              })
            else
              TextField(
                controller: controller,
                minLines: type == 'short_answer' ? 4 : 1,
                maxLines: type == 'short_answer' ? 8 : 1,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '输入答案',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: submitting ? null : onSubmit,
                  child: const Text('提交本题'),
                ),
                const SizedBox(width: 12),
                if (graded != null)
                  Expanded(
                    child: Text(
                      '${graded!['score']}/${graded!['max_score']}  ${graded!['feedback']}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
