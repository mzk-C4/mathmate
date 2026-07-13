import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/models/library_question.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/services/library_question_service.dart';
import 'package:mathmate/pages/exam_history_page.dart';

/// 自由组卷 —— 从题库选题，本地组卷，支持单选/填空，自动评分
class ExamCreationPage extends StatefulWidget {
  const ExamCreationPage({super.key});

  @override
  State<ExamCreationPage> createState() => _ExamCreationPageState();
}

class _ExamCreationPageState extends State<ExamCreationPage> {
  final AbilityScoreService _ability = AbilityScoreService();
  final LibraryQuestionService _qs = LibraryQuestionService();

  final Set<String> _selectedDims = <String>{};
  int _count = 10;
  double _diffMin = 0.1, _diffMax = 0.9;
  bool _incChoice = true, _incBlank = true;
  bool _loading = false;

  ColorScheme get cs => Theme.of(context).colorScheme;

  List<String> get _dimensions => _ability.currentDimensionNames;

  List<String> _sectionsFor(String dim) =>
      UserRadarProfile.dimensionTagsFor(_ability.currentGrade)[dim] ?? [dim];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('自由组卷'),
        backgroundColor: cs.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: '历史记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExamHistoryPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _dimensionChips(),
              const SizedBox(height: 24),
              _countSlider(),
              const SizedBox(height: 20),
              _difficultySlider(),
              const SizedBox(height: 20),
              _typeChips(),
              const SizedBox(height: 32),
              _startButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dimensionChips() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('选择维度（可多选）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (_selectedDims.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectedDims.clear()),
                  child: const Text('清空', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dimensions.map((d) {
              final bool sel = _selectedDims.contains(d);
              return FilterChip(
                label: Text(d),
                selected: sel,
                onSelected: (v) => setState(() => v ? _selectedDims.add(d) : _selectedDims.remove(d)),
                selectedColor: cs.primaryContainer,
                checkmarkColor: cs.primary,
                labelStyle: TextStyle(color: sel ? cs.onPrimaryContainer : cs.onSurface, fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ],
      );

  Widget _countSlider() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('题目数量：$_count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Slider(
            value: _count.toDouble(),
            min: 5,
            max: 30,
            divisions: 5,
            label: '$_count',
            activeColor: cs.primary,
            onChanged: (v) => setState(() => _count = v.round()),
          ),
        ],
      );

  Widget _difficultySlider() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '难度范围：${_diffMin.toStringAsFixed(1)} ~ ${_diffMax.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          RangeSlider(
            values: RangeValues(_diffMin, _diffMax),
            min: 0.0,
            max: 1.0,
            divisions: 10,
            labels: RangeLabels(_diffMin.toStringAsFixed(1), _diffMax.toStringAsFixed(1)),
            activeColor: cs.primary,
            onChanged: (v) => setState(() {
              _diffMin = v.start;
              _diffMax = v.end;
            }),
          ),
        ],
      );

  Widget _typeChips() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('题型', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('选择题'),
                selected: _incChoice,
                onSelected: (v) {
                  if (_incChoice || _incBlank || v) setState(() => _incChoice = v);
                },
                selectedColor: cs.primaryContainer,
                checkmarkColor: cs.primary,
              ),
              FilterChip(
                label: const Text('填空题'),
                selected: _incBlank,
                onSelected: (v) {
                  if (_incChoice || _incBlank || v) setState(() => _incBlank = v);
                },
                selectedColor: cs.primaryContainer,
                checkmarkColor: cs.primary,
              ),
            ],
          ),
        ],
      );

  Widget _startButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: _loading ? null : _start,
          icon: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.assignment_rounded),
          label: Text(_loading ? '正在获取题目...' : '开始组卷', style: const TextStyle(fontSize: 16)),
        ),
      );

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      // ====== [摆拍] 5 道演示题目 ======
      const List<LibraryQuestion> demoQuestions = [
        LibraryQuestion(id: 'demo_shulie', section: '数列', type: '单选题',
          content: r'在等差数列 $\{a_n\}$ 中，$a_1=2$，$a_3=8$，则 $a_5$ 等于',
          options: ['A. 12', 'B. 14', 'C. 16', 'D. 18'], answer: 'B',
          solution: r'公差 $d=\frac{a_3-a_1}{2}=\frac{8-2}{2}=3$，$a_5=a_3+2d=8+6=14$',
          difficulty: 0.4, knowledgePoints: ['等差数列'], sourceRef: ''),
        LibraryQuestion(id: 'demo_sanjiao', section: '三角函数', type: '单选题',
          content: r'$\sin 30^\circ + \cos 60^\circ$ 的值为',
          options: ['A. 0.5', 'B. 1', 'C. 1.5', 'D. 2'], answer: 'B',
          solution: r'$\sin 30^\circ=\frac{1}{2}$，$\cos 60^\circ=\frac{1}{2}$，和为 $1$',
          difficulty: 0.3, knowledgePoints: ['三角函数值'], sourceRef: ''),
        LibraryQuestion(id: 'demo_kongjian', section: '立体几何', type: '填空题',
          content: r'正方体的棱长为 $3$，则其体积为',
          answer: '27',
          solution: r'正方体体积 $V=a^3=3^3=27$',
          difficulty: 0.2, knowledgePoints: ['体积计算'], sourceRef: ''),
        LibraryQuestion(id: 'demo_xiangliang', section: '向量', type: '填空题',
          content: r'已知 $\vec{a}=(2,0)$，$\vec{b}=(1,3)$，则 $\vec{a}\cdot\vec{b}=$',
          answer: '2',
          solution: r'$\vec{a}\cdot\vec{b}=2\times1+0\times3=2$',
          difficulty: 0.35, knowledgePoints: ['向量数量积'], sourceRef: ''),
        LibraryQuestion(id: 'demo_zuhe', section: '计数原理', type: '单选题',
          content: r'从 $6$ 本不同的书中选出 $2$ 本，不同的选法有',
          options: ['A. 12 种', 'B. 15 种', 'C. 30 种', 'D. 36 种'], answer: 'B',
          solution: r'$C_6^2=\frac{6\times5}{2}=15$',
          difficulty: 0.4, knowledgePoints: ['组合计数'], sourceRef: ''),
      ];
      // ====== [摆拍] 演示题目 END ======

      setState(() => _loading = false);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _ExamSolverPage(questions: demoQuestions, title: '数列三角+平面几何+组合计数'),
        ),
      );
      return;
      // ====== 下面为正常组卷逻辑（摆拍时跳过） ======

      // 确定要获取的 sections（多选或全部）
      final List<String> targetSections;
      if (_selectedDims.isNotEmpty) {
        targetSections = <String>[];
        for (final String dim in _selectedDims) {
          targetSections.addAll(_sectionsFor(dim));
        }
        targetSections.toSet().toList(); // 去重
      } else {
        targetSections = <String>['函数', '函数与导数', '数列', '三角函数', '向量', '立体几何', '解析几何', '概率统计', '计数原理', '代数', '集合与逻辑', '复数', '不等式'];
      }

      // 构建题型过滤
      final List<String> types = <String>[];
      if (_incChoice) types.add('单选题');
      if (_incBlank) types.add('填空题');

      // 从题库获取并筛选
      final List<LibraryQuestion> pool = <LibraryQuestion>[];
      for (final String sec in targetSections) {
        try {
          final List<LibraryQuestion> items = await _qs.fetchBySection(sec);
          for (final LibraryQuestion q in items) {
            if (q.difficulty >= _diffMin &&
                q.difficulty <= _diffMax &&
                types.contains(q.type)) {
              pool.add(q);
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      if (pool.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前条件下没有可用题目，请调整筛选条件')),
        );
        setState(() => _loading = false);
        return;
      }

      pool.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
      final List<LibraryQuestion> selected = pool.take(_count).toList();

      setState(() => _loading = false);
      if (!mounted) return;

      // 跳转到答题页
      final Map<String, dynamic>? result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => _ExamSolverPage(
            questions: selected,
            title: _selectedDims.isNotEmpty ? _selectedDims.join('+') : '综合组卷',
          ),
        ),
      );

      // 答题完成后保存历史
      if (result != null && mounted) {
        await _saveHistory(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('组卷失败: $e')));
      }
    }
  }

  Future<void> _saveHistory(Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('exam_history') ?? <String>[];
    result['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    result['time'] = DateTime.now().toIso8601String();
    raw.insert(0, jsonEncode(result));
    if (raw.length > 50) raw.removeLast(); // 最多保留 50 条
    await prefs.setStringList('exam_history', raw);
  }
}

// =============================================================================
// 答题页（内联实现，不依赖后端）
// =============================================================================

class _ExamSolverPage extends StatefulWidget {
  final List<LibraryQuestion> questions;
  final String title;
  const _ExamSolverPage({required this.questions, required this.title});

  @override
  State<_ExamSolverPage> createState() => _ExamSolverPageState();
}

class _ExamSolverPageState extends State<_ExamSolverPage> {
  final Map<int, String> _answers = <int, String>{};
  Map<int, bool>? _results;
  bool _showResult = false;
  int _currentIndex = 0;

  ColorScheme get cs => Theme.of(context).colorScheme;
  LibraryQuestion get q => widget.questions[_currentIndex];
  bool get _isChoice => q.type == '单选题';
  int get _total => widget.questions.length;
  bool get _allAnswered => _answers.length == _total;

  int get _correctCount => _results?.values.where((v) => v).length ?? 0;

  void _selectOption(String label) => setState(() => _answers[_currentIndex] = label);
  void _next() { if (_currentIndex < _total - 1) setState(() => _currentIndex++); }
  void _prev() { if (_currentIndex > 0) setState(() => _currentIndex--); }

  void _submitAll() {
    final Map<int, bool> graded = <int, bool>{};
    for (int i = 0; i < _total; i++) {
      final q = widget.questions[i];
      final user = (_answers[i] ?? '').trim();
      if (user.isEmpty) continue;
      if (q.type == '单选题') {
        final clean = q.answer.replaceAll(RegExp(r'[\$\(\)\s]'), '');
        graded[i] = user == clean;
      } else {
        graded[i] = _normalizedEquals(user, q.answer);
      }
    }
    setState(() { _results = graded; _showResult = true; });
  }

  bool _normalizedEquals(String a, String b) {
    if (a.toLowerCase() == b.toLowerCase()) return true;
    final na = _tryNum(a), nb = _tryNum(b);
    if (na != null && nb != null) return (na - nb).abs() < 1e-9;
    return false;
  }

  double? _tryNum(String s) {
    final d = double.tryParse(s);
    if (d != null) return d;
    final slash = s.indexOf('/');
    if (slash > 0 && slash < s.length - 1) {
      final a = double.tryParse(s.substring(0, slash));
      final b = double.tryParse(s.substring(slash + 1));
      if (a != null && b != null && b != 0) return a / b;
    }
    return null;
  }

  void _redoWrong() {
    final wrongIndices = <int>[];
    for (final e in (_results ?? <int, bool>{}).entries) {
      if (!e.value) wrongIndices.add(e.key);
    }
    setState(() {
      _showResult = false;
      _results = null;
      if (wrongIndices.isNotEmpty) _currentIndex = wrongIndices.first;
      for (final i in wrongIndices) { _answers.remove(i); }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showResult) return _buildResultPage();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('${widget.title}（${_currentIndex + 1}/$_total）'),
        backgroundColor: cs.surface,
        actions: [
          if (_allAnswered)
            TextButton.icon(
              onPressed: _submitAll,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('交卷'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildMeta(),
              const SizedBox(height: 16),
              _buildContent(),
              const SizedBox(height: 20),
              if (_isChoice) _buildOptions() else _buildBlank(),
              const SizedBox(height: 20),
              _buildActionRow(),
              const SizedBox(height: 12),
              // 进度指示器
              LinearProgressIndicator(
                value: (_currentIndex + 1) / _total,
                backgroundColor: cs.surfaceContainerHighest,
                color: cs.primary,
              ),
              const SizedBox(height: 8),
              // 已答题目标记
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: List<Widget>.generate(_total, (i) {
                  final bool answered = _answers.containsKey(i);
                  return GestureDetector(
                    onTap: () => setState(() => _currentIndex = i),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _currentIndex
                            ? cs.primary
                            : answered
                                ? cs.primary.withValues(alpha: 0.3)
                                : cs.surfaceContainerHighest,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i == _currentIndex || answered ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeta() {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(q.section, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        ...List<Widget>.generate(
          (q.difficulty * 5).round().clamp(1, 5),
          (_) => const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
        ),
        const Spacer(),
        Text(q.type, style: TextStyle(fontSize: 12, color: cs.outline)),
      ],
    );
  }

  Widget _buildContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: _LatexRenderer(text: q.content, cs: cs, baseFontSize: 16),
    );
  }

  Widget _buildOptions() {
    final List<String> options = q.options ?? <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: options.map((opt) {
        String label, text;
        final paren = RegExp(r'^\$*\s*\(\s*([A-D])\s*\)\s*\$*\s*(.*)').firstMatch(opt);
        if (paren != null) {
          label = paren.group(1)!;
          text = paren.group(2)!;
        } else {
          final dot = RegExp(r'^\$*\s*([A-D])\s*\$*\s*[\.、．]\s*(.*)').firstMatch(opt);
          if (dot != null) {
            label = dot.group(1)!;
            text = dot.group(2)!;
          } else {
            label = opt.length >= 2 && opt[1] == '.' ? opt.substring(0, 1) : opt;
            text = opt.length >= 2 && opt[1] == '.' ? opt.substring(2).trim() : opt;
          }
        }
        label = label.replaceAll(RegExp(r'[^A-D]'), '');
        if (label.isEmpty) label = opt;

        final bool selected = _answers[_currentIndex] == label;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _selectOption(label),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : cs.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5), width: selected ? 2 : 1),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? cs.primary : cs.surfaceContainerHighest,
                    ),
                    alignment: Alignment.center,
                    child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : cs.onSurface)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _LatexRenderer(text: text, cs: cs, baseFontSize: 15)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBlank() {
    return TextField(
      controller: TextEditingController(text: _answers[_currentIndex] ?? ''),
      onChanged: (v) => _answers[_currentIndex] = v,
      decoration: InputDecoration(
        hintText: '请输入答案...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.edit_rounded),
      ),
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: <Widget>[
        if (_currentIndex > 0)
          OutlinedButton.icon(
            onPressed: _prev,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('上一题'),
          ),
        const Spacer(),
        if (_currentIndex < _total - 1)
          FilledButton.icon(
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('下一题'),
          ),
      ],
    );
  }

  Widget _buildResultPage() {
    final results = _results ?? <int, bool>{};
    final int correct = _correctCount;
    final int total = _total;
    final int answered = results.length;
    final double pct = total > 0 ? correct / total * 100 : 0;
    final int wrongCount = answered - correct;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('答题结果'), backgroundColor: cs.surface, leading: const SizedBox()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 20),
              Icon(pct >= 80 ? Icons.emoji_events_rounded : pct >= 60 ? Icons.sentiment_satisfied : Icons.sentiment_neutral_rounded,
                  size: 72, color: pct >= 80 ? Colors.amber : pct >= 60 ? cs.primary : Colors.orange),
              const SizedBox(height: 16),
              Text('$correct / $total', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: cs.onSurface)),
              Text('正确率 ${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
              if (wrongCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('错了 $wrongCount 道题', style: TextStyle(fontSize: 14, color: Colors.red.shade400)),
                ),
              const SizedBox(height: 24),
              // 逐题回顾
              ...List<Widget>.generate(total, (i) {
                final bool done = results.containsKey(i);
                final bool isCorrect = results[i] ?? false;
                final q = widget.questions[i];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: !done ? cs.surfaceContainerHighest : (isCorrect ? Colors.green : Colors.red),
                          ),
                          alignment: Alignment.center,
                          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: done ? Colors.white : cs.onSurface)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(q.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                        ),
                        if (done)
                          Text(isCorrect ? '✓' : '✗', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isCorrect ? Colors.green : Colors.red)),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
              if (wrongCount > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _redoWrong,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('重做错题（$wrongCount 道）', style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(<String, dynamic>{
                      'title': widget.title, 'total': total, 'correct': correct,
                      'pct': pct.toStringAsFixed(0),
                      'questions': widget.questions.map((q) => q.content).toList(),
                      'answers': _answers.map((k, v) => MapEntry(k.toString(), v)),
                      'results': results.map((k, v) => MapEntry(k.toString(), v)),
                    });
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('完成', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LaTeX 公式渲染（复用 flutter_math_fork，Wrap 布局防 Android 闪退）
// =============================================================================

class _LatexRenderer extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  final double baseFontSize;

  const _LatexRenderer({required this.text, required this.cs, this.baseFontSize = 14});

  @override
  Widget build(BuildContext context) {
    final Color c = cs.onSurface;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    if (text.contains(r'$')) return _buildMixed(c);
    if (RegExp(r'\\[a-zA-Z]+').hasMatch(text)) {
      return Math.tex(text, mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: baseFontSize, color: c),
        onErrorFallback: (err) => Text(text, style: TextStyle(fontSize: baseFontSize, color: c)),
      );
    }
    return Text(text, style: TextStyle(fontSize: baseFontSize, color: c, height: 1.6));
  }

  Widget _buildMixed(Color c) {
    final List<_LatexSegment> segs = <_LatexSegment>[];
    final String t = text;
    int i = 0;
    while (i < t.length) {
      if (i + 1 < t.length && t.substring(i).startsWith(r'$$')) {
        final end = t.indexOf(r'$$', i + 2);
        if (end != -1) {
          final f = t.substring(i + 2, end).trim();
          if (f.isNotEmpty) segs.add(_LatexSegment(f, latex: true, display: true));
          i = end + 2;
          continue;
        }
      }
      if (t[i] == r'$') {
        final end = t.indexOf(r'$', i + 1);
        if (end != -1) {
          final f = t.substring(i + 1, end);
          if (f.trim().isNotEmpty) segs.add(_LatexSegment(f, latex: true));
          i = end + 1;
          continue;
        }
      }
      final n1 = t.indexOf(r'$$', i), n2 = t.indexOf(r'$', i);
      int n = -1;
      if (n1 != -1 && n2 != -1) n = n1 < n2 ? n1 : n2;
      else if (n1 != -1) n = n1;
      else if (n2 != -1) n = n2;
      final plain = n == -1 ? t.substring(i) : t.substring(i, n);
      if (plain.isNotEmpty) segs.add(_LatexSegment(plain));
      if (n == -1) break;
      i = n;
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: segs.map((seg) {
        if (!seg.latex) return Text(seg.text, style: TextStyle(fontSize: baseFontSize, color: c, height: 1.6));
        try {
          return Math.tex(seg.text,
            mathStyle: seg.display ? MathStyle.display : MathStyle.text,
            textStyle: TextStyle(fontSize: baseFontSize, color: c),
            onErrorFallback: (err) => Text(seg.text, style: TextStyle(fontSize: baseFontSize, color: c)),
          );
        } catch (_) {
          return Text(seg.text, style: TextStyle(fontSize: baseFontSize, color: c));
        }
      }).toList(),
    );
  }
}

class _LatexSegment {
  final String text;
  final bool latex;
  final bool display;
  const _LatexSegment(this.text, {this.latex = false, this.display = false});
}
