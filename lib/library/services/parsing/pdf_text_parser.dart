import 'package:pdfrx/pdfrx.dart';

class PdfParseResult {
  const PdfParseResult({required this.text, required this.pageCount});

  final String text;
  final int pageCount;
}

/// Extracts the selectable text layer from a PDF.
///
/// Scanned PDFs may legitimately return an empty string; image OCR can be
/// added as a separate fallback without changing the ingestion contract.
class PdfTextParser {
  Future<PdfParseResult> extractFromPath(String path) async {
    final PdfDocument document = await PdfDocument.openFile(path);
    try {
      final List<String> pages = <String>[];
      for (final PdfPage page in document.pages) {
        final PdfPageRawText? pageText = await page.loadText();
        final String text = pageText?.fullText.trim() ?? '';
        if (text.isNotEmpty) pages.add(text);
      }
      return PdfParseResult(
        text: pages.join('\n\n'),
        pageCount: document.pages.length,
      );
    } finally {
      await document.dispose();
    }
  }
}
