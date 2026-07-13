import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mathmate/services/exam_api.dart';

void main() {
  test('healthCheck rejects a successful HTML response', () async {
    final client = MockClient(
      (_) async => http.Response('<html>Flutter app</html>', 200),
    );
    final api = ExamApi(
      baseUrl: 'https://example.test',
      client: client,
      tokenProvider: () => 'test-token',
    );

    expect(await api.healthCheck(), isFalse);
  });

  test('healthCheck validates JSON and sends the bearer token', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/exams/health');
      expect(request.headers['authorization'], 'Bearer test-token');
      return http.Response(
        '{"status":"ok"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ExamApi(
      baseUrl: 'https://example.test',
      client: client,
      tokenProvider: () => 'test-token',
    );

    expect(await api.healthCheck(), isTrue);
  });

  test('availableQuestionCount sends filters with authentication', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/exams/available-count');
      expect(request.headers['authorization'], 'Bearer test-token');
      expect(request.body, contains('"boards":["代数","解析几何"]'));
      return http.Response(
        '{"available_count":2}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ExamApi(
      baseUrl: 'https://example.test',
      client: client,
      tokenProvider: () => 'test-token',
    );

    final count = await api.availableQuestionCount(
      boards: const ['代数', '解析几何'],
      questionTypes: const ['choice'],
    );

    expect(count, 2);
  });

  test('protected requests report an actionable message for 401', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"detail":"Valid Bearer token required"}',
        401,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = ExamApi(
      baseUrl: 'https://example.test',
      client: client,
      tokenProvider: () => null,
    );

    await expectLater(
      api.availableQuestionCount(),
      throwsA(
        isA<ExamApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', '登录状态已失效，请重新登录'),
      ),
    );
  });
}
