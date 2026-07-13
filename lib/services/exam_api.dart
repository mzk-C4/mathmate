import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mathmate/services/auth_service.dart';

/// 考试系统 API 客户端
///
/// 对接 ExamSystem FastAPI 后端，支持：
/// - 创建考试（按板块/难度/题型组卷）
/// - 逐题提交答案
/// - 完成考试获取成绩报告
class ExamApi {
  ExamApi({
    required this.baseUrl,
    http.Client? client,
    String? Function()? tokenProvider,
  }) : _client = client ?? http.Client(),
       _tokenProvider = tokenProvider ?? (() => AuthService().token);

  final String baseUrl;
  final http.Client _client;
  final String? Function() _tokenProvider;

  static const Duration _requestTimeout = Duration(seconds: 30);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// 创建一场考试（组卷）
  Future<Map<String, dynamic>> createExam({
    required String studentId,
    required String title,
    required int totalCount,
    String? board,
    List<String>? boards,
    double? difficultyMin,
    double? difficultyMax,
    List<String>? questionTypes,
  }) async {
    return _postJson('/api/exams/create', {
      'student_id': studentId,
      'title': title,
      'total_count': totalCount,
      if (board != null) 'board': board,
      if (boards != null && boards.isNotEmpty) 'boards': boards,
      if (difficultyMin != null) 'difficulty_min': difficultyMin,
      if (difficultyMax != null) 'difficulty_max': difficultyMax,
      if (questionTypes != null) 'question_types': questionTypes,
    });
  }

  /// 获取考试详情
  Future<Map<String, dynamic>> getExam(int examId) async {
    final response = await _client
        .get(_uri('/api/exams/$examId'), headers: _headers())
        .timeout(_requestTimeout);
    return _decodeResponse(response);
  }

  /// 查询当前筛选条件下的可用题量
  Future<int> availableQuestionCount({
    String? board,
    List<String>? boards,
    double? difficultyMin,
    double? difficultyMax,
    List<String>? questionTypes,
  }) async {
    final result = await _postJson('/api/exams/available-count', {
      if (board != null) 'board': board,
      if (boards != null && boards.isNotEmpty) 'boards': boards,
      if (difficultyMin != null) 'difficulty_min': difficultyMin,
      if (difficultyMax != null) 'difficulty_max': difficultyMax,
      if (questionTypes != null) 'question_types': questionTypes,
    });
    return (result['available_count'] as num?)?.toInt() ?? 0;
  }

  /// 提交单题答案
  Future<Map<String, dynamic>> submitAnswer({
    required int examId,
    required String studentId,
    required int questionId,
    required String studentAnswer,
    String? imageUrl,
  }) async {
    return _postJson('/api/exams/submit-answer', {
      'exam_id': examId,
      'student_id': studentId,
      'question_id': questionId,
      'student_answer': studentAnswer,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  /// 完成考试，获取成绩报告
  Future<Map<String, dynamic>> finishExam({
    required int examId,
    required String studentId,
  }) async {
    return _postJson('/api/exams/finish', {
      'exam_id': examId,
      'student_id': studentId,
    });
  }

  /// 上传图片（OCR 手写答案）
  Future<Map<String, dynamic>> uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/grading/upload-image'),
    );
    request.headers.addAll(_headers());
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );
    final streamed = await _client.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    return _decodeResponse(response);
  }

  /// 健康检查
  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(_uri('/api/exams/health'), headers: _headers())
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> && decoded['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client
        .post(
          _uri(path),
          headers: _headers(json: true),
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);
    return _decodeResponse(response);
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    final token = _tokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded as Map<String, dynamic>;
    }
    if (response.statusCode == 401) {
      throw ExamApiException(401, '登录状态已失效，请重新登录');
    }
    final message = decoded is Map<String, dynamic>
        ? decoded['detail']
        : decoded;
    throw ExamApiException(response.statusCode, message.toString());
  }
}

class ExamApiException implements Exception {
  ExamApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ExamApiException($statusCode): $message';
}

/// 考试系统配置
class ExamSystemConfig {
  /// 本地开发地址
  static const String localUrl = 'http://10.0.2.2:8000';

  /// 生产环境地址（已部署：Nginx /api/exams/ /api/grading/ → ExamSystem :8000）
  static const String productionUrl = 'https://mathmate.top';

  /// 是否使用本地地址
  static const bool useLocal = false;

  /// 当前生效的 baseUrl
  static String get baseUrl => useLocal ? localUrl : productionUrl;
}
