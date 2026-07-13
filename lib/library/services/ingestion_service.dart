import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/library/models/study_material.dart';
import 'package:mathmate/library/services/classification_service.dart';
import 'package:mathmate/library/services/material_repository.dart';
import 'package:mathmate/library/services/parsing/image_ocr_parser.dart';
import 'package:mathmate/library/services/parsing/pdf_text_parser.dart';
import 'package:mathmate/services/app_logger.dart';
import 'package:path_provider/path_provider.dart';

/// 资料采集服务：采集 → 落盘 → 解析 → 分类 → 入库 的总调度
///
/// L1 闭环：图片(板书) / PDF(真题) 两类可用；
/// PPT / 录音 为 MVP 占位（抛 UnsupportedError，UI 层已拦截）。
class IngestionService {
  IngestionService._();
  static final IngestionService instance = IngestionService._();

  final ImagePicker _picker = ImagePicker();
  final ImageOcrParser _ocr = ImageOcrParser();
  final PdfTextParser _pdf = PdfTextParser();
  final ClassificationService _classifier = ClassificationService();

  /// 采集指定类型资料并入库
  ///
  /// [onProgress] 回调用于 UI 显示进度文案；用户取消返回 null。
  Future<StudyMaterial?> ingest(
    MaterialKind kind, {
    void Function(String text)? onProgress,
  }) async {
    onProgress?.call('正在选择资料…');

    File? source;
    String fileName = '';

    switch (kind) {
      case MaterialKind.image:
        final XFile? xfile = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
        if (xfile == null) return null; // 用户取消
        source = File(xfile.path);
        fileName = xfile.name;
        break;
      case MaterialKind.pdf:
        final FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: <String>['pdf'],
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return null;
        final String? p = result.files.single.path;
        if (p == null) return null;
        source = File(p);
        fileName = result.files.single.name;
        break;
      case MaterialKind.pptx:
      case MaterialKind.audio:
        throw UnsupportedError('该类型暂未接入（即将上线）');
    }

    // 落盘到 app docs/study_materials，统一管理，避免临时文件丢失
    final Directory dir = await getApplicationDocumentsDirectory();
    final Directory libDir = Directory('${dir.path}/study_materials');
    if (!await libDir.exists()) {
      await libDir.create(recursive: true);
    }
    final String safeName = fileName.replaceAll(RegExp(r'[\\/]'), '_');
    final File dest = File(
      '${libDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    await source.copy(dest.path);
    final int sizeBytes = await dest.length();

    // 解析（提取文本）
    onProgress?.call('正在解析内容…');
    String extractedText = '';
    if (kind == MaterialKind.image) {
      extractedText = await _ocr.extractFromPath(dest.path);
    } else if (kind == MaterialKind.pdf) {
      final PdfParseResult result = await _pdf.extractFromPath(dest.path);
      extractedText = result.text;
    }

    // AI 分类
    onProgress?.call('AI 正在分类整理…');
    final MaterialTags? tags = await _classifier.classify(
      kind: kind,
      extractedText: extractedText,
      fileName: fileName,
    );

    final StudyMaterial material = StudyMaterial.create(
      kind: kind,
      localPath: dest.path,
      fileName: fileName,
      sizeBytes: sizeBytes,
      extractedText: extractedText,
      tags: tags ?? MaterialTags.unknown(),
    );
    await MaterialRepository.instance.save(material);
    AppLogger.instance.info('[Ingestion] 入库成功: ${material.title}');
    onProgress?.call('已入库');
    return material;
  }
}
