import 'package:flutter/material.dart';
import 'package:mathmate/wrong_book/models/wrong_question.dart';
import 'package:mathmate/wrong_book/services/wrong_question_repository.dart';

class WrongQuestionBookPage extends StatefulWidget {
  const WrongQuestionBookPage({super.key});

  @override
  State<WrongQuestionBookPage> createState() => _WrongQuestionBookPageState();
}

class _WrongQuestionBookPageState extends State<WrongQuestionBookPage> {
  final WrongQuestionRepository _repository = WrongQuestionRepository.instance;
  String _query = '';
  bool _showMastered = false;

  List<WrongQuestion> get _items {
    final String query = _query.trim().toLowerCase();
    return _repository.all(includeMastered: _showMastered).where((item) {
      if (query.isEmpty) return true;
      return <String>[
        item.content,
        item.board,
        ...item.knowledgePoints,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<WrongQuestion> items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('智能错题本')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (String value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索题目、板块或知识点',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('显示已掌握题目'),
            value: _showMastered,
            onChanged: (bool value) => setState(() => _showMastered = value),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _query.isEmpty ? '还没有错题记录' : '没有匹配的错题',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final WrongQuestion item = items[index];
                      return _WrongQuestionCard(
                        item: item,
                        onMasteredChanged: (bool value) async {
                          await _repository.setMastered(item.id, value);
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WrongQuestionCard extends StatelessWidget {
  const _WrongQuestionCard({
    required this.item,
    required this.onMasteredChanged,
  });

  final WrongQuestion item;
  final ValueChanged<bool> onMasteredChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.content,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Checkbox(
                  value: item.mastered,
                  onChanged: (bool? value) => onMasteredChanged(value ?? false),
                ),
              ],
            ),
            if (item.knowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.knowledgePoints
                    .map((String point) => Chip(label: Text(point)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '你的答案：${item.studentAnswer}',
              style: TextStyle(color: colors.error),
            ),
            Text(
              '正确答案：${item.standardAnswer}',
              style: const TextStyle(color: Colors.green),
            ),
            if (item.explanation.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text('解析：${item.explanation}'),
            ],
            const SizedBox(height: 8),
            Text(
              '${item.board.isEmpty ? '未分类' : item.board} · 已错 ${item.wrongCount} 次',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
