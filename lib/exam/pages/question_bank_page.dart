import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:mathmate/exam/models/question.dart';
import 'package:mathmate/exam/services/question_api.dart';

/// 题库浏览页（参考实现，给队员开发考试功能做接入样板）
///
/// 接云端 https://mathmate.top/api/library/：
/// 板块筛选 + 难度筛选 + 关键词 → 列表 → 点题看详情（题干/选项/答案/解析）。
class QuestionBankPage extends StatefulWidget {
  const QuestionBankPage({super.key});

  @override
  State<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends State<QuestionBankPage> {
  ColorScheme get cs => Theme.of(context).colorScheme;
  final QuestionApi _api = QuestionApi();

  List<Question> _questions = const <Question>[];
  List<SectionStat> _sections = const <SectionStat>[];
  int _total = 0;
  bool _loading = true;
  String? _error;

  String _filterSection = ''; // '' = 全部
  String _filterDiff = ''; // '' / 基础/中等/较难/挑战
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _loadSections();
    _reload();
  }

  Future<void> _loadSections() async {
    try {
      final s = await _api.fetchSections();
      if (mounted) setState(() => _sections = s);
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      double? dmin, dmax;
      switch (_filterDiff) {
        case '基础':
          dmin = 0.0;
          dmax = 0.4;
          break;
        case '中等':
          dmin = 0.4;
          dmax = 0.6;
          break;
        case '较难':
          dmin = 0.6;
          dmax = 0.8;
          break;
        case '挑战':
          dmin = 0.8;
          dmax = 1.0;
          break;
      }
      final res = await _api.fetchQuestions(
        section: _filterSection.isNotEmpty ? _filterSection : null,
        dmin: dmin,
        dmax: dmax,
        q: _keyword.isNotEmpty ? _keyword : null,
        page: 1,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _questions = res.items;
          _total = res.total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('题库')),
      body: Column(
        children: <Widget>[
          _buildStatHeader(),
          _buildSearchField(),
          if (_sections.isNotEmpty) _buildSectionChips(),
          _buildDiffChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // 统计头部
  Widget _buildStatHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.library_books_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text('云端题库',
              style: TextStyle(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$_total 题',
              style: TextStyle(
                  color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          Text('${_sections.length} 板块',
              style: TextStyle(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜题干 / 知识点…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onSubmitted: (_) => _reload(),
        onChanged: (v) => _keyword = v,
      ),
    );
  }

  // 板块筛选
  Widget _buildSectionChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          _chip('全部', _filterSection.isEmpty, () => _setSection('')),
          ..._sections.map(
            (s) => _chip('${s.section} (${s.count})',
                _filterSection == s.section, () => _setSection(s.section)),
          ),
        ],
      ),
    );
  }

  void _setSection(String s) {
    setState(() => _filterSection = s);
    _reload();
  }

  // 难度筛选
  Widget _buildDiffChips() {
    const diffs = <String>['', '基础', '中等', '较难', '挑战'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 6,
        children: diffs
            .map((d) => _chip(d.isEmpty ? '全部难度' : d, _filterDiff == d,
                () => setState(() {
                      _filterDiff = d;
                      _reload();
                    })))
            .toList(),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.cloud_off, size: 48, color: cs.outline),
              const SizedBox(height: 8),
              Text('加载失败', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('$_error',
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.inbox, size: 48, color: cs.outline),
            const SizedBox(height: 8),
            const Text('暂无题目'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _questions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, int i) => _QuestionTile(
          q: _questions[i],
          onTap: () => _showDetail(_questions[i]),
        ),
      ),
    );
  }

  void _showDetail(Question q) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuestionDetailSheet(q: q),
    );
  }
}

/// 题目列表项
class _QuestionTile extends StatelessWidget {
  final Question q;
  final VoidCallback onTap;
  const _QuestionTile({required this.q, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color diffColor = <String, Color>{
      '基础': Colors.green,
      '中等': Colors.orange,
      '较难': Colors.deepOrange,
      '挑战': Colors.red,
    }[q.difficultyLabel] ??
        Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(q.typeIcon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(q.type,
                      style: TextStyle(
                          fontSize: 10, color: cs.onPrimaryContainer)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(q.section,
                      style: TextStyle(
                          fontSize: 10, color: cs.onSecondaryContainer)),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: diffColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${q.difficultyLabel} ${q.difficulty.toStringAsFixed(2)}',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRect(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 42),
                child: _TexContent(q.content, cs, fontSize: 13),
              ),
            ),
            if (q.knowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: q.knowledgePoints
                    .take(3)
                    .map((k) => Text('#$k',
                        style: TextStyle(
                            fontSize: 10, color: cs.tertiary)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 题目详情（题干 / 选项 / 答案 / 解析）
class _QuestionDetailSheet extends StatelessWidget {
  final Question q;
  const _QuestionDetailSheet({required this.q});

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final options = parseOptions(q.options);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          controller: controller,
          children: <Widget>[
            Center(
              child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: cs.outline,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _meta(q.type, cs.primaryContainer, cs.onPrimaryContainer),
                const SizedBox(width: 6),
                _meta(q.section, cs.secondaryContainer, cs.onSecondaryContainer),
                const SizedBox(width: 6),
                _meta('${q.difficultyLabel} ${q.difficulty.toStringAsFixed(2)}',
                    cs.tertiaryContainer, cs.onTertiaryContainer),
              ],
            ),
            const SizedBox(height: 14),
            const Text('题干',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            _TexContent(q.content, cs, fontSize: 15),
            if (options.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text('选项',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              ...options.map((o) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('${o.letter}. ',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Expanded(child: _TexContent(o.text, cs, fontSize: 15)),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('答案',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.green)),
                  const SizedBox(height: 4),
                  _TexContent(q.answer.isNotEmpty ? q.answer : '（暂无）', cs, fontSize: 14),
                ],
              ),
            ),
            if (q.solution.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text('解析',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              _TexContent(q.solution, cs, fontSize: 14),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child:
            Text(text, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
      );
}

// ---------------------------------------------------------------------------
// LaTeX 公式渲染组件（与 question_solver_page.dart 的 _LatexRenderer 同逻辑）
// ---------------------------------------------------------------------------

/// 渲染混合普通文本 + $...$ 内联公式 + $$...$$ 块级公式
class _TexContent extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  final double fontSize;

  const _TexContent(this.text, this.cs, {this.fontSize = 14});

  bool get _hasLatex => RegExp(r'\\[a-zA-Z]+').hasMatch(text);

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    // 无 $ 无 LaTeX 命令 → 纯文本
    if (!text.contains(r'$') && !_hasLatex) {
      return Text(text, style: TextStyle(fontSize: fontSize, color: cs.onSurface, height: 1.6));
    }

    // 整体 $$...$$ 单行块级公式
    if (text.startsWith(r'$$') && text.endsWith(r'$$') && text.length > 4) {
      final formula = text.substring(2, text.length - 2).trim();
      return Math.tex(formula,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
          onErrorFallback: (err) =>
              Text(formula, style: TextStyle(fontSize: fontSize, color: cs.onSurface)));
    }

    // 无 $ 但含 LaTeX 命令 → 整体渲染
    if (!text.contains(r'$') && _hasLatex) {
      return Math.tex(text,
          mathStyle: MathStyle.text,
          textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
          onErrorFallback: (err) =>
              Text(text, style: TextStyle(fontSize: fontSize, color: cs.onSurface)));
    }

    // 内联 $...$ 混合解析
    return _buildMixed();
  }

  Widget _buildMixed() {
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
              child: Math.tex(formula,
                  mathStyle: MathStyle.text,
                  textStyle: TextStyle(fontSize: fontSize, color: cs.onSurface),
                  onErrorFallback: (err) => Text(formula,
                      style: TextStyle(fontSize: fontSize, color: cs.onSurface))),
            ));
          }
          i = end + 1;
          continue;
        }
      }
      final next = text.indexOf(r'$', i);
      final String plain = next == -1 ? text.substring(i) : text.substring(i, next);
      if (plain.isNotEmpty) {
        spans.add(TextSpan(
            text: plain,
            style: TextStyle(fontSize: fontSize, color: cs.onSurface, height: 1.6)));
      }
      if (next == -1) break;
      i = next;
    }
    return Text.rich(TextSpan(children: spans));
  }
}
