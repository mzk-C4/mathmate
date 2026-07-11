import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

class LatexCompileResult {
  final String? pdfPath;
  final String? error;
  LatexCompileResult({this.pdfPath, this.error});
  bool get success => pdfPath != null;
}

class LatexCompiler {
  Future<LatexCompileResult> compile(String markdown) async {
    try {
      final ByteData fontData = await rootBundle.load('assets/fonts/simhei.ttf');
      final pw.Font font = pw.Font.ttf(fontData);

      final String cleaned = _cleanLatexForPdf(_stripMarkdown(markdown));

      final pw.Document pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(36),
          build: (pw.Context context) {
            return <pw.Widget>[
              pw.Header(
                level: 0,
                child: pw.Text(
                  'MathMate 助手 — 解答',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    font: font,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Paragraph(
                text: cleaned,
                style: pw.TextStyle(fontSize: 12, font: font, height: 1.6),
              ),
            ];
          },
        ),
      );

      final Directory dir = await getApplicationDocumentsDirectory();
      final String path = '${dir.path}/mathmate_chat_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final File file = File(path);
      await file.writeAsBytes(await pdf.save());

      return LatexCompileResult(pdfPath: path);
    } catch (e) {
      return LatexCompileResult(error: e.toString());
    }
  }

  Future<void> openPdf(String pdfPath) async {
    await OpenFile.open(pdfPath);
  }

  String _stripMarkdown(String text) {
    text = text.replaceAllMapped(
      RegExp(r'\$\$([\s\S]*?)\$\$'),
      (Match m) => m.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\$([^\$\n]+?)\$'),
      (Match m) => m.group(1) ?? '',
    );
    return text
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '')
        .trim();
  }

  String _cleanLatexForPdf(String latex) {
    latex = latex.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'),
      (Match m) => '(${m.group(1)})/(${m.group(2)})',
    );
    latex = latex.replaceAllMapped(
      RegExp(r'\\sqrt\{([^{}]*)\}'),
      (Match m) => 'sqrt(${m.group(1)})',
    );
    latex = latex.replaceAllMapped(
      RegExp(r'\^(\{[^{}]*\}|\S)'),
      (Match m) {
        final String exp = m.group(1) ?? '';
        final String e = exp.startsWith('{') ? exp.substring(1, exp.length - 1) : exp;
        return _toSuperscript(e);
      },
    );
    latex = latex.replaceAllMapped(
      RegExp(r'_\{(\S+?)\}'),
      (Match m) => _toSubscript(m.group(1) ?? ''),
    );
    latex = latex.replaceAllMapped(
      RegExp(r'\\sqrt(\d)'),
      (Match m) => 'sqrt${m.group(1)}',
    );
    return latex
        .replaceAll(r'\\times', '×')
        .replaceAll(r'\\div', '÷')
        .replaceAll(r'\\pm', '±')
        .replaceAll(r'\\mp', '∓')
        .replaceAll(r'\\leq', '≤')
        .replaceAll(r'\\geq', '≥')
        .replaceAll(r'\\neq', '≠')
        .replaceAll(r'\\approx', '≈')
        .replaceAll(r'\\equiv', '≡')
        .replaceAll(r'\\infty', '∞')
        .replaceAll(r'\\alpha', 'α')
        .replaceAll(r'\\beta', 'β')
        .replaceAll(r'\\gamma', 'γ')
        .replaceAll(r'\\delta', 'δ')
        .replaceAll(r'\\pi', 'π')
        .replaceAll(r'\\theta', 'θ')
        .replaceAll(r'\\lambda', 'λ')
        .replaceAll(r'\\mu', 'μ')
        .replaceAll(r'\\sigma', 'σ')
        .replaceAll(r'\\phi', 'φ')
        .replaceAll(r'\\psi', 'ψ')
        .replaceAll(r'\\omega', 'ω')
        .replaceAll(r'\\Delta', 'Δ')
        .replaceAll(r'\\Sigma', 'Σ')
        .replaceAll(r'\\Omega', 'Ω')
        .replaceAll(r'\\Gamma', 'Γ')
        .replaceAll(r'\\cdot', '·')
        .replaceAll(r'\\ldots', '...')
        .replaceAll(r'\\rightarrow', '→')
        .replaceAll(r'\\leftarrow', '←')
        .replaceAll(r'\\Rightarrow', '⇒')
        .replaceAll(r'\\Leftarrow', '⇐')
        .replaceAll(r'\\leftrightarrow', '↔')
        .replaceAll(r'\\in', '∈')
        .replaceAll(r'\\notin', '∉')
        .replaceAll(r'\\subset', '⊂')
        .replaceAll(r'\\subseteq', '⊆')
        .replaceAll(r'\\cup', '∪')
        .replaceAll(r'\\cap', '∩')
        .replaceAll(r'\\forall', '∀')
        .replaceAll(r'\\exists', '∃')
        .replaceAll(r'\\partial', '∂')
        .replaceAll(r'\\nabla', '∇')
        .replaceAll(r'\\sin', 'sin')
        .replaceAll(r'\\cos', 'cos')
        .replaceAll(r'\\tan', 'tan')
        .replaceAll(r'\\cot', 'cot')
        .replaceAll(r'\\sec', 'sec')
        .replaceAll(r'\\csc', 'csc')
        .replaceAll(r'\\arcsin', 'arcsin')
        .replaceAll(r'\\arccos', 'arccos')
        .replaceAll(r'\\arctan', 'arctan')
        .replaceAll(r'\\log', 'log')
        .replaceAll(r'\\ln', 'ln')
        .replaceAll(r'\\lg', 'lg')
        .replaceAll(r'\\lim', 'lim')
        .replaceAll(r'\\sum', '∑')
        .replaceAll(r'\\prod', '∏')
        .replaceAll(r'\\int', '∫')
        .replaceAll(r'\\begin\{cases\}', '')
        .replaceAll(r'\\end\{cases\}', '')
        .replaceAll(r'\\begin\{aligned\}', '')
        .replaceAll(r'\\end\{aligned\}', '')
        .replaceAll(r'\\begin\{matrix\}', '')
        .replaceAll(r'\\end\{matrix\}', '')
        .replaceAll(r'\\begin\{bmatrix\}', '[')
        .replaceAll(r'\\end\{bmatrix\}', ']')
        .replaceAll(r'\\begin\{pmatrix\}', '(')
        .replaceAll(r'\\end\{pmatrix\}', ')')
        .replaceAll(r'\\begin\{vmatrix\}', '|')
        .replaceAll(r'\\end\{vmatrix\}', '|')
        .replaceAll(r'\\begin\{smallmatrix\}', '')
        .replaceAll(r'\\end\{smallmatrix\}', '')
        .replaceAll(r'\\left', '')
        .replaceAll(r'\\right', '')
        .replaceAll(r'\\ ', ' ')
        .replaceAll(r'\\quad', '  ')
        .replaceAll(r'\\qquad', '    ')
        .replaceAll(r'\\\\', '\n')
        .replaceAll(r'\\\{', '{')
        .replaceAll(r'\\\}', '}')
        .replaceAll(r'\{', '')
        .replaceAll(r'\}', '')
        .replaceAll(r'\_', '_')
        .replaceAll(r'\^', '^')
        .replaceAll(RegExp(r'\\text\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\textbf\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\textit\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\mathsf\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\mathrm\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\mathbf\{([^}]*)\}'), r'$1')
        .replaceAll(RegExp(r'\\mathit\{([^}]*)\}'), r'$1')
        .replaceAll(r'\\_', '_')
        .replaceAll(r'\\%', '%')
        .replaceAll('√', 'sqrt(')
        .replaceAllMapped(
          RegExp(r'\\sqrt\{([^{}]*)\}'),
          (Match m) => 'sqrt(${m.group(1)})',
        )
        .replaceAllMapped(
          RegExp(r'sqrt\(([^)]+)\)\s*(\d)'),
          (Match m) => 'sqrt(${m.group(1)})^${m.group(2)}',
        )
        .trim();
  }

  String _toSuperscript(String s) {
    const Map<String, String> supMap = {
      '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
      '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
      '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
      'n': 'ⁿ', 'i': 'ⁱ',
    };
    return s.split('').map((c) => supMap[c] ?? c).join('');
  }

  String _toSubscript(String s) {
    const Map<String, String> subMap = {
      '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
      '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
      '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
      'a': 'ₐ', 'e': 'ₑ', 'o': 'ₒ', 'x': 'ₓ',
      'i': 'ᵢ', 'j': 'ⱼ', 'n': 'ₙ', 'm': 'ₘ', 'r': 'ᵣ',
      's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ', 'v': 'ᵥ',
    };
    return s.split('').map((c) => subMap[c] ?? c).join('');
  }
}
