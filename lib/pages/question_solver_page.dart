import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/models/library_question.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/services/ability_score_service.dart';

/// 答题页面 —— 从题库选题后进入，支持单选/填空，提交后看解析
class QuestionSolverPage extends StatefulWidget {
  final LibraryQuestion question;

  const QuestionSolverPage({super.key, required this.question});

  @override
  State<QuestionSolverPage> createState() => _QuestionSolverPageState();
}

class _QuestionSolverPageState extends State<QuestionSolverPage> {
  final AbilityScoreService _abilityService = AbilityScoreService();

  /// 用户选择的选项（单选题）
  String? _selectedOption;

  /// 用户填写的答案（填空题）
  final TextEditingController _answerController = TextEditingController();

  /// 是否已提交
  bool _submitted = false;

  /// 是否正确
  bool? _isCorrect;

  ColorScheme get cs => Theme.of(context).colorScheme;

  LibraryQuestion get q => widget.question;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  bool get _isChoice => q.type == '单选题' || q.type == '多选题';

  void _submit() {
    final String userAnswer = _isChoice
        ? (_selectedOption ?? '')
        : _answerController.text.trim();

    if (userAnswer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个答案')),
      );
      return;
    }

    // 判断对错
    final bool correct = _isChoice
        ? userAnswer == q.answer
        : userAnswer.toLowerCase() == q.answer.toLowerCase();

    // 记录到能力评分
    final int dimIndex = _dimensionIndex;
    if (dimIndex >= 0) {
      _abilityService.recordAnswer(
        dimensionIndex: dimIndex,
        isCorrect: correct,
        difficulty: q.difficulty * 5.0, // 0~1 → 1~5 映射
      );
    }

    setState(() {
      _submitted = true;
      _isCorrect = correct;
    });
  }

  /// 根据 section 反查维度索引
  int get _dimensionIndex {
    for (final MapEntry<String, List<String>> e
        in UserRadarProfile.dimensionTags.entries) {
      if (e.value.contains(q.section)) {
        return UserRadarProfile.dimensionNames.indexOf(e.key);
      }
    }
    return -1;
  }

  void _retry() {
    setState(() {
      _submitted = false;
      _isCorrect = null;
      _selectedOption = null;
      _answerController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          q.type,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 题目来源 + 分类标签
              _buildMeta(),
              const SizedBox(height: 16),

              // 题目内容
              _buildQuestionContent(),
              const SizedBox(height: 24),

              // 选项 / 填空
              if (_isChoice)
                _buildOptions()
              else
                _buildFillBlank(),
              const SizedBox(height: 24),

              // 提交按钮 / 结果展示
              if (!_submitted)
                _buildSubmitButton()
              else
                _buildResult(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeta() {
    return Row(
      children: <Widget>[
        if (q.sourceRef.isNotEmpty) ...[
          Icon(Icons.menu_book_rounded, size: 14, color: cs.outline),
          const SizedBox(width: 4),
          Text(q.sourceRef, style: TextStyle(fontSize: 12, color: cs.outline)),
          const SizedBox(width: 12),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            q.section,
            style: TextStyle(
              fontSize: 11,
              color: cs.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 难度星级
        ...List<Widget>.generate(
          (q.difficulty * 5).round().clamp(1, 5),
          (i) => const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
        ),
      ],
    );
  }

  Widget _buildQuestionContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: _LatexRenderer(
        text: q.content,
        cs: cs,
        baseFontSize: 16,
      ),
    );
  }

  Widget _buildOptions() {
    final List<String> options = q.options ?? <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: options.map((opt) {
        // 解析选项：如 "A. {−1, 0}" → label="A", text="{−1, 0}"
        final String label = opt.length >= 2 && opt[1] == '.'
            ? opt.substring(0, 1)
            : opt;
        final String text = opt.length >= 2 && opt[1] == '.'
            ? opt.substring(2).trim()
            : opt;

        final bool isSelected = _selectedOption == label;
        final bool showCorrect = _submitted && label == q.answer;
        final bool showWrong = _submitted && isSelected && label != q.answer;

        Color? bgColor;
        Color? borderColor;
        if (showCorrect) {
          bgColor = Colors.green.withValues(alpha: 0.1);
          borderColor = Colors.green;
        } else if (showWrong) {
          bgColor = Colors.red.withValues(alpha: 0.1);
          borderColor = Colors.red;
        } else if (isSelected) {
          bgColor = cs.primaryContainer;
          borderColor = cs.primary;
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: _submitted
                ? null
                : () => setState(() => _selectedOption = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: bgColor ?? cs.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: borderColor ?? cs.outlineVariant.withValues(alpha: 0.5),
                  width: borderColor != null ? 2 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected && !showWrong
                          ? cs.primary
                          : showCorrect
                              ? Colors.green
                              : showWrong
                                  ? Colors.red
                                  : cs.surfaceContainerHighest,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: (isSelected || showCorrect || showWrong)
                            ? Colors.white
                            : cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LatexRenderer(
                      text: text,
                      cs: cs,
                      baseFontSize: 15,
                    ),
                  ),
                  if (showCorrect)
                    const Icon(Icons.check_circle, color: Colors.green, size: 22),
                  if (showWrong)
                    const Icon(Icons.cancel, color: Colors.red, size: 22),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFillBlank() {
    return TextField(
      controller: _answerController,
      enabled: !_submitted,
      decoration: InputDecoration(
        hintText: '请输入你的答案...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.edit_rounded),
      ),
      style: const TextStyle(fontSize: 16),
      onSubmitted: _submitted ? null : (_) => _submit(),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.check_rounded),
        label: const Text('提交答案', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildResult() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isCorrect == true
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isCorrect == true
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 结果标题
          Row(
            children: <Widget>[
              Icon(
                _isCorrect == true
                    ? Icons.emoji_events_rounded
                    : Icons.lightbulb_outline_rounded,
                color: _isCorrect == true ? Colors.green : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                _isCorrect == true ? '回答正确！' : '答案不正确',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _isCorrect == true ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 正确答案
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('正确答案：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 4),
              Expanded(
                child: _isChoice
                    ? Text(
                        q.answer,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : _LatexRenderer(
                        text: q.answer,
                        cs: cs,
                        baseFontSize: 14,
                        bold: true,
                        color: cs.primary,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 解析
          const Text('解析：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 6),
          _LatexRenderer(
            text: q.solution,
            cs: cs,
            baseFontSize: 14,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),

          // 操作按钮
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重新作答'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('下一题'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LaTeX 公式渲染组件（复用项目已有 flutter_math_fork）
// ---------------------------------------------------------------------------

/// 渲染混合普通文本 + $...$ 内联公式 + $$...$$ 块级公式的组件
///
/// 移动端 Android 已验证可用。解析逻辑兼容：
/// - `$...$` 内联公式 → `Math.tex()` inline
/// - `$$...$$` 块级公式 → `Math.tex()` display
/// - `\(...\)` / `\[...\]` 备选分隔符
/// - 无 $ 包裹的纯 LaTeX 命令（如 `\frac{a}{b}`）→ 整体渲染
class _LatexRenderer extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  final double baseFontSize;
  final bool bold;
  final Color? color;

  const _LatexRenderer({
    required this.text,
    required this.cs,
    this.baseFontSize = 14,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final Color effectiveColor = color ?? cs.onSurface;
    final FontWeight weight = bold ? FontWeight.w700 : FontWeight.w400;

    // 空文本
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    // 含 $，走混合解析
    if (text.contains(r'$')) {
      return _buildMixed();
    }

    // 无 $ 但含 LaTeX 命令，尝试整体 Math.tex 渲染
    if (_hasLatexCommands(text)) {
      return Math.tex(
        text,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: baseFontSize, color: effectiveColor, fontWeight: weight),
        onErrorFallback: (err) => Text(
          text,
          style: TextStyle(fontSize: baseFontSize, color: effectiveColor, fontWeight: weight, height: 1.6),
        ),
      );
    }

    // 纯文本
    return Text(
      text,
      style: TextStyle(fontSize: baseFontSize, color: effectiveColor, fontWeight: weight, height: 1.6),
    );
  }

  bool _hasLatexCommands(String s) => RegExp(r'\\[a-zA-Z]+').hasMatch(s);

  /// 混合模式：逐字符解析 $...$ 和 $$...$$，其余为普通文本
  Widget _buildMixed() {
    final String t = text;
    final List<InlineSpan> spans = <InlineSpan>[];
    final Color effectiveColor = color ?? cs.onSurface;
    final FontWeight weight = bold ? FontWeight.w700 : FontWeight.w400;

    int i = 0;
    while (i < t.length) {
      // 检查 $$ 块级公式开始
      if (i + 1 < t.length && t.substring(i).startsWith(r'$$')) {
        final end = t.indexOf(r'$$', i + 2);
        if (end != -1) {
          final formula = t.substring(i + 2, end).trim();
          if (formula.isNotEmpty) {
            spans.add(WidgetSpan(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Math.tex(
                  formula,
                  mathStyle: MathStyle.display,
                  textStyle: TextStyle(fontSize: baseFontSize, color: effectiveColor),
                  onErrorFallback: (err) => Text(formula,
                      style: TextStyle(fontSize: baseFontSize, color: effectiveColor)),
                ),
              ),
            ));
          }
          i = end + 2;
          continue;
        }
      }

      // 检查 $ 内联公式
      if (t[i] == r'$') {
        final end = t.indexOf(r'$', i + 1);
        if (end != -1) {
          final formula = t.substring(i + 1, end);
          if (formula.trim().isNotEmpty) {
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                formula,
                mathStyle: MathStyle.text,
                textStyle: TextStyle(fontSize: baseFontSize, color: effectiveColor, fontWeight: weight),
                onErrorFallback: (err) => Text(formula,
                    style: TextStyle(fontSize: baseFontSize, color: effectiveColor)),
              ),
            ));
          }
          i = end + 1;
          continue;
        }
      }

      // 普通文本：累积到下一个 $ 或 $$
      final next1 = t.indexOf(r'$$', i);
      final next2 = t.indexOf(r'$', i);
      int next = -1;
      if (next1 != -1 && next2 != -1) {
        next = next1 < next2 ? next1 : next2;
      } else if (next1 != -1) {
        next = next1;
      } else if (next2 != -1) {
        next = next2;
      }

      final String plain = next == -1 ? t.substring(i) : t.substring(i, next);
      if (plain.isNotEmpty) {
        spans.add(TextSpan(
          text: plain,
          style: TextStyle(fontSize: baseFontSize, color: effectiveColor, fontWeight: weight, height: 1.6),
        ));
      }
      if (next == -1) break;
      i = next;
    }

    return Text.rich(TextSpan(children: spans));
  }
}
