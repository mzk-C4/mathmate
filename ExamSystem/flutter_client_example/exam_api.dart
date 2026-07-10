import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ExamApi {
  ExamApi({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> createExam({
    required String studentId,
    required String title,
    required int totalCount,
    String? board,
    double? difficultyMin,
    double? difficultyMax,
    List<String>? questionTypes,
  }) async {
    return _postJson('/api/exams/create', {
      'student_id': studentId,
      'title': title,
      'total_count': totalCount,
      'board': board,
      'difficulty_min': difficultyMin,
      'difficulty_max': difficultyMax,
      'question_types': questionTypes,
    });
  }

  Future<Map<String, dynamic>> getExam(int examId) async {
    final response = await _client.get(_uri('/api/exams/$examId'));
    return _decodeResponse(response);
  }

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
      'image_url': imageUrl,
    });
  }

  Future<Map<String, dynamic>> finishExam({
    required int examId,
    required String studentId,
  }) async {
    return _postJson('/api/exams/finish', {
      'exam_id': examId,
      'student_id': studentId,
    });
  }

  Future<Map<String, dynamic>> uploadImage(File imageFile) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/grading/upload-image'),
    );
    request.files.add(
      await http.MultipartFile.fromPath('file', imageFile.path),
    );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded as Map<String, dynamic>;
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
