import 'dart:io';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class LatexCompileResult {
  final String? pdfPath;
  final String? error;
  LatexCompileResult({this.pdfPath, this.error});
  bool get success => pdfPath != null;
}

class LatexCompiler {
  static const String _pdflatexPath =
      r'F:\software\texlive\2025\bin\windows\pdflatex.exe';

  /// 将 Markdown+LaTeX 内容编译为 PDF
  Future<LatexCompileResult> compile(String markdown) async {
    final String texContent = _markdownToLatex(markdown);

    final Directory tempDir = await getTemporaryDirectory();
    final String baseName =
        'mathmate_${DateTime.now().millisecondsSinceEpoch}';
    final File texFile = File('${tempDir.path}/$baseName.tex');

    try {
      await texFile.writeAsString(texContent);

      // 运行两次 pdflatex 以解决交叉引用
      for (int i = 0; i < 2; i++) {
        final ProcessResult result = await Process.run(
          _pdflatexPath,
          <String>[
            '-interaction=nonstopmode',
            '-output-directory',
            tempDir.path,
            texFile.path,
          ],
          workingDirectory: tempDir.path,
        );

        if (result.exitCode != 0) {
          final String log = result.stdout.toString();
          // 提取首个错误
          final RegExp errorRe = RegExp(r'^! (.+)$', multiLine: true);
          final RegExpMatch? match = errorRe.firstMatch(log);
          final String errorMsg =
              match != null ? match.group(1)! : 'pdflatex 编译失败';
          return LatexCompileResult(error: errorMsg);
        }
      }

      final String pdfPath = '${tempDir.path}/$baseName.pdf';
      final File pdfFile = File(pdfPath);
      if (await pdfFile.exists()) {
        return LatexCompileResult(pdfPath: pdfPath);
      }
      return LatexCompileResult(error: 'PDF 文件未生成');
    } catch (e) {
      return LatexCompileResult(error: e.toString());
    }
  }

  /// 打开 PDF 文件
  Future<void> openPdf(String pdfPath) async {
    await OpenFile.open(pdfPath);
  }

  String _markdownToLatex(String input) {
    // 1. 保护代码块
    final List<String> codeBlocks = <String>[];
    String text = input.replaceAllMapped(
      RegExp(r'```[\s\S]*?```'),
      (Match m) {
        codeBlocks.add(m.group(0)!);
        return '\x00CODE${codeBlocks.length - 1}\x00';
      },
    );

    // 2. 保护行内代码
    final List<String> inlineCodes = <String>[];
    text = text.replaceAllMapped(
      RegExp(r'`[^`]+`'),
      (Match m) {
        inlineCodes.add(m.group(0)!);
        return '\x00ICODE${inlineCodes.length - 1}\x00';
      },
    );

    // 3. 保护 $$...$$ 块级公式
    final List<String> displayMaths = <String>[];
    text = text.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (Match m) {
        displayMaths.add(m.group(1)!);
        return '\x00DMATH${displayMaths.length - 1}\x00';
      },
    );

    // 4. 保护 $...$ 行内公式
    final List<String> inlineMaths = <String>[];
    text = text.replaceAllMapped(
      RegExp(r'\$(.+?)\$'),
      (Match m) {
        inlineMaths.add(m.group(1)!);
        return '\x00IMATH${inlineMaths.length - 1}\x00';
      },
    );

    // 5. 转换 Markdown 语法为 LaTeX
    final List<String> lines = text.split('\n');
    final StringBuffer buf = StringBuffer();
    bool inList = false;
    bool inEnum = false;

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // 空行 → 结束列表环境
      if (line.trim().isEmpty) {
        if (inList) {
          buf.writeln(r'\end{itemize}');
          inList = false;
        }
        if (inEnum) {
          buf.writeln(r'\end{enumerate}');
          inEnum = false;
        }
        // 检查下一行是不是新列表的开始
        if (i + 1 < lines.length &&
            (lines[i + 1].trim().startsWith('- ') ||
                RegExp(r'^\d+\.\s').hasMatch(lines[i + 1].trim()))) {
          // skip, let next iteration handle it
        }
        buf.writeln();
        continue;
      }

      // 处理 **...** 加粗
      line = line.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (Match m) => '\\textbf{${m.group(1)}}',
      );

      // ### 三级标题
      if (line.startsWith('### ')) {
        if (inList) {
          buf.writeln(r'\end{itemize}');
          inList = false;
        }
        if (inEnum) {
          buf.writeln(r'\end{enumerate}');
          inEnum = false;
        }
        buf.writeln(
            '\\subsubsection*{${_escapeLatex(line.substring(4).trim())}}');
        continue;
      }

      // ## 二级标题
      if (line.startsWith('## ')) {
        if (inList) {
          buf.writeln(r'\end{itemize}');
          inList = false;
        }
        if (inEnum) {
          buf.writeln(r'\end{enumerate}');
          inEnum = false;
        }
        buf.writeln(
            '\\subsection*{${_escapeLatex(line.substring(3).trim())}}');
        continue;
      }

      // # 一级标题
      if (line.startsWith('# ')) {
        if (inList) {
          buf.writeln(r'\end{itemize}');
          inList = false;
        }
        if (inEnum) {
          buf.writeln(r'\end{enumerate}');
          inEnum = false;
        }
        buf.writeln(
            '\\section*{${_escapeLatex(line.substring(2).trim())}}');
        continue;
      }

      // 无序列表
      if (line.trim().startsWith('- ')) {
        if (!inList) {
          buf.writeln(r'\begin{itemize}');
          inList = true;
        }
        if (inEnum) {
          buf.writeln(r'\end{enumerate}');
          inEnum = false;
        }
        buf.writeln(
            '  \\item ${_restoreLine(line.trim().substring(2), inlineMaths, displayMaths, codeBlocks, inlineCodes)}');
        continue;
      }

      // 有序列表
      final RegExp enumRe = RegExp(r'^(\d+)\.\s(.+)$');
      final RegExpMatch? enumMatch = enumRe.firstMatch(line.trim());
      if (enumMatch != null) {
        if (!inEnum) {
          buf.writeln(r'\begin{enumerate}');
          inEnum = true;
        }
        if (inList) {
          buf.writeln(r'\end{itemize}');
          inList = false;
        }
        buf.writeln(
            '  \\item ${_restoreLine(enumMatch.group(2)!, inlineMaths, displayMaths, codeBlocks, inlineCodes)}');
        continue;
      }

      // 普通段落
      if (inList) {
        buf.writeln(r'\end{itemize}');
        inList = false;
      }
      if (inEnum) {
        buf.writeln(r'\end{enumerate}');
        inEnum = false;
      }

      final String restored = _restoreLine(
          line, inlineMaths, displayMaths, codeBlocks, inlineCodes);
      buf.writeln(restored);

      // 块级公式后添加空行
      if (line.contains('\x00DMATH')) {
        buf.writeln();
      }
    }

    // 关闭未结束的环境
    if (inList) buf.writeln(r'\end{itemize}');
    if (inEnum) buf.writeln(r'\end{enumerate}');

    // 6. 恢复保护的内容并转换为 LaTeX 格式
    String body = buf.toString();
    for (int i = 0; i < inlineMaths.length; i++) {
      body = body.replaceAll('\x00IMATH$i\x00', '\$${inlineMaths[i]}\$');
    }
    for (int i = 0; i < displayMaths.length; i++) {
      body = body.replaceAll(
          '\x00DMATH$i\x00', '\\[\n${displayMaths[i]}\n\\]');
    }
    for (int i = 0; i < codeBlocks.length; i++) {
      final String code = codeBlocks[i]
          .replaceAll(RegExp(r'^```\w*\n?'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      body = body.replaceAll(
          '\x00CODE$i\x00', '\\begin{verbatim}\n$code\n\\end{verbatim}');
    }
    for (int i = 0; i < inlineCodes.length; i++) {
      final String code =
          inlineCodes[i].replaceAll('`', '').trim();
      body = body.replaceAll(
          '\x00ICODE$i\x00', '\\texttt{$code}');
    }

    return _wrapDocument(body);
  }

  String _restoreLine(String line, List<String> imaths, List<String> dmaths,
      List<String> codes, List<String> icodes) {
    for (int i = 0; i < imaths.length; i++) {
      line = line.replaceAll('\x00IMATH$i\x00', '\$${imaths[i]}\$');
    }
    for (int i = 0; i < dmaths.length; i++) {
      line = line.replaceAll('\x00DMATH$i\x00', '\\[\n${dmaths[i]}\n\\]');
    }
    for (int i = 0; i < codes.length; i++) {
      final String code = codes[i]
          .replaceAll(RegExp(r'^```\w*\n?'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      line = line.replaceAll(
          '\x00CODE$i\x00', '\\begin{verbatim}\n$code\n\\end{verbatim}');
    }
    for (int i = 0; i < icodes.length; i++) {
      line = line.replaceAll('\x00ICODE$i\x00', '\\texttt{${icodes[i].replaceAll('`', '').trim()}}');
    }
    return line;
  }

  String _escapeLatex(String text) {
    return text
        .replaceAll(r'\', r'\textbackslash{}')
        .replaceAll('&', r'\&')
        .replaceAll('%', r'\%')
        .replaceAll('#', r'\#')
        .replaceAll('_', r'\_')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('~', r'\textasciitilde{}')
        .replaceAll('^', r'\textasciicircum{}');
  }

  String _wrapDocument(String body) {
    return r'''
\documentclass[12pt,a4paper]{ctexart}

\usepackage[utf8]{inputenc}
\usepackage{amsmath,amssymb,amsthm}
\usepackage{geometry}
\usepackage{enumitem}
\usepackage{xcolor}
\usepackage{hyperref}

\geometry{margin=2.5cm}
\hypersetup{colorlinks=true,linkcolor=blue,urlcolor=blue}

\title{蓝心数学助手 — 解答}
\author{MathMate}
\date{\today}

\begin{document}
\maketitle

'''
        '$body'
        r'''
\end{document}
''';
  }
}
