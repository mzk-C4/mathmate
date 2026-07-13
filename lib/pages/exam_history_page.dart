import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 考试历史记录页 —— 查看过去组卷的成绩
class ExamHistoryPage extends StatefulWidget {
  const ExamHistoryPage({super.key});

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _loading = true;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('exam_history') ?? <String>[];
    final List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
    for (final String s in raw) {
      try {
        parsed.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (mounted) setState(() { _records = parsed; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('考试历史'), backgroundColor: cs.surface),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.history_rounded, size: 64, color: cs.outline),
                      const SizedBox(height: 12),
                      Text('暂无考试记录', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (_, i) => _buildCard(_records[i]),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final String title = r['title'] as String? ?? '组卷';
    final int total = (r['total'] as num?)?.toInt() ?? 0;
    final int correct = (r['correct'] as num?)?.toInt() ?? 0;
    final String pct = r['pct'] as String? ?? '0';
    final String time = r['time'] as String? ?? '';
    final String displayTime = time.length >= 16 ? time.substring(0, 16).replaceAll('T', ' ') : time;

    final bool good = (int.tryParse(pct) ?? 0) >= 60;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: good ? Colors.green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Text('$pct%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: good ? Colors.green : Colors.orange)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Text('$correct / $total 正确 · $displayTime', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
