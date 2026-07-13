import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/services/auth_service.dart';

void main() {
  const userId = 'user-1';

  test('profile-only response is successful during login restoration', () {
    final response = AuthResponse(
      user: AuthUser(
        id: userId,
        username: 'tester',
        email: 'tester@example.com',
        role: 'user',
      ),
    );

    expect(response.ok, isTrue);
  });

  test('token response is successful and error response is not', () {
    expect(AuthResponse(token: 'token').ok, isTrue);
    expect(AuthResponse(error: 'failed').ok, isFalse);
  });
}
