import 'package:flutter/material.dart';

class ExamResultPage extends StatelessWidget {
  const ExamResultPage({super.key, required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final wrongQuestions = report['wrong_questions'] as List<dynamic>? ?? [];
    final boardAnalysis = report['board_analysis'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('测试报告')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '总分：${report['total_score']} / ${report['max_score']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '正确率：${(((report['accuracy'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 24),
          Text('板块分析', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final item in boardAnalysis)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['board'].toString()),
              subtitle: Text('正确 ${item['correct']} / ${item['total']}'),
              trailing: Text('${item['score']} / ${item['max_score']}'),
            ),
          const SizedBox(height: 24),
          Text('错题回顾', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (wrongQuestions.isEmpty)
            const Text('本次没有错题')
          else
            for (final item in wrongQuestions)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['content']?.toString() ?? ''),
                      const SizedBox(height: 8),
                      Text('你的答案：${item['student_answer'] ?? ''}'),
                      Text('标准答案：${item['standard_answer'] ?? ''}'),
                      if (item['explanation'] != null)
                        Text('解析：${item['explanation']}'),
                      if (item['llm_feedback'] != null)
                        Text('反馈：${item['llm_feedback']}'),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
