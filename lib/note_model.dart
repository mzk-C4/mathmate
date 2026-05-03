import 'package:flutter/material.dart';

class Note {
  final String title;
  final String content;
  final DateTime createTime;
  final DateTime updateTime;
  final Color textColor;
  final List<String> imagePaths;
  final bool isFavorite;
  final String category;
  final List<String> tags;
  final bool hasHistoryLink;
  final String noteType; // 'type' = 打字笔记, 'handwriting' = 手写笔记, 'pdf' = PDF导入
  final String pdfPath; // PDF文件路径，仅 noteType='pdf' 时有效
  final List<Map<String, String>> linkedHistories; // 嵌入笔记的搜题历史卡片

  Note({
    required this.title,
    required this.content,
    required this.createTime,
    required this.updateTime,
    this.textColor = Colors.black,
    this.imagePaths = const [],
    this.isFavorite = false,
    this.category = '其他',
    this.tags = const [],
    this.hasHistoryLink = false,
    this.noteType = 'type',
    this.pdfPath = '',
    this.linkedHistories = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'content': content,
      'createTime': createTime.toIso8601String(),
      'updateTime': updateTime.toIso8601String(),
      'textColor': textColor.value.toString(),
      'imagePaths': imagePaths,
      'isFavorite': isFavorite,
      'category': category,
      'tags': tags,
      'hasHistoryLink': hasHistoryLink,
      'noteType': noteType,
      'pdfPath': pdfPath,
      'linkedHistories': linkedHistories,
    };
  }

  static Note fromJson(Map<String, dynamic> json) {
    String parsedCategory = '其他';
    if (json['category'] != null) {
      String raw = json['category'].toString();
      if (raw == 'NoteCategory.work')
        parsedCategory = '代数';
      else if (raw == 'NoteCategory.life')
        parsedCategory = '几何';
      else if (raw == 'NoteCategory.study')
        parsedCategory = '微积分';
      else if (raw == 'NoteCategory.other')
        parsedCategory = '其他';
      else
        parsedCategory = raw;
    }

    return Note(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createTime: DateTime.parse(json['createTime'] ?? DateTime.now().toIso8601String()),
      updateTime: DateTime.parse(json['updateTime'] ?? json['createTime']),
      textColor: Color(
        int.parse(json['textColor'] ?? Colors.black.value.toString()),
      ),
      imagePaths: List<String>.from(json['imagePaths'] ?? []),
      isFavorite: json['isFavorite'] ?? false,
      category: parsedCategory,
      tags: List<String>.from(json['tags'] ?? []),
      hasHistoryLink: json['hasHistoryLink'] ?? false,
      noteType: json['noteType'] ?? 'type',
      pdfPath: json['pdfPath'] ?? '',
      linkedHistories: json['linkedHistories'] != null
          ? List<Map<String, String>>.from(
              (json['linkedHistories'] as List).map(
                (e) => Map<String, String>.from(e as Map),
              ),
            )
          : [],
    );
  }
}