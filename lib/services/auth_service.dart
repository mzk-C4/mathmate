import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 用户信息模型
class AuthUser {
  final String id;
  final String username;
  final String email;
  final String role;
  final String? createdAt;

  AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.createdAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      createdAt: json['createdAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'role': role,
        'createdAt': createdAt,
      };
}

/// 登录/注册响应
class AuthResponse {
  final String? token;
  final AuthUser? user;
  final String? error;

  AuthResponse({this.token, this.user, this.error});
  bool get ok => token != null;
}

/// 认证服务 —— 注册/登录/个人信息/Token 管理。
///
/// 与服务端 auth_server.js 通信，Token 存储在 SharedPreferences。
class AuthService {
  // 本地开发：Web 用 localhost，Android 模拟器用 10.0.2.2（真机请改局域网 IP）
  static final String _baseUrl = kIsWeb
      ? 'http://localhost:3002/api/auth'
      : 'http://10.0.2.2:3002/api/auth';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  static AuthService? _instance;
  factory AuthService() => _instance ??= AuthService._();
  AuthService._();

  String? _token;
  AuthUser? _user;

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  AuthUser? get user => _user;

  /// 从本地存储恢复登录状态
  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        _user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }
    // 验证 token 仍有效
    if (_token != null) {
      final profile = await getProfile();
      if (profile != null) {
        _user = profile;
        return true;
      }
      // token 失效，清除
      await _clear();
    }
    return false;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_tokenKey, _token!);
    } else {
      await prefs.remove(_tokenKey);
    }
    if (_user != null) {
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
    } else {
      await prefs.remove(_userKey);
    }
  }

  Future<void> _clear() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<AuthResponse> _post(String path, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        _token = data['token'] as String?;
        if (data['user'] != null) {
          _user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
        }
        await _save();
        return AuthResponse(token: _token, user: _user);
      }
      return AuthResponse(error: data['error'] as String? ?? '请求失败');
    } catch (e) {
      return AuthResponse(error: '网络错误: $e');
    }
  }

  Future<AuthResponse> _get(String path) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_token ?? ''}',
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return AuthResponse(user: AuthUser.fromJson(data));
      }
      return AuthResponse(error: data['error'] as String? ?? '请求失败');
    } catch (e) {
      return AuthResponse(error: '网络错误: $e');
    }
  }

  /// 注册（邮箱/手机 + 验证码 + 密码，无邀请码）
  Future<AuthResponse> register({
    required String username,
    required String password,
    String email = '',
    String phone = '',
    String code = '',
  }) {
    return _post('register', {
      'username': username,
      'password': password,
      'email': email,
      'phone': phone,
      'code': code,
    });
  }

  /// 发送验证码到邮箱/手机
  Future<Map<String, dynamic>> sendCode({String email = '', String phone = ''}) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/send-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'phone': phone}),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': '网络错误: $e'};
    }
  }

  /// 验证验证码
  Future<Map<String, dynamic>> verifyCode({String email = '', String phone = '', required String code}) async {
    try {
      final r = await http.post(
        Uri.parse('$_baseUrl/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'phone': phone, 'code': code}),
      ).timeout(const Duration(seconds: 10));
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': '网络错误: $e'};
    }
  }

  /// 登录
  Future<AuthResponse> login({
    required String username,
    required String password,
  }) {
    return _post('login', {
      'username': username,
      'password': password,
    });
  }

  /// 获取当前用户信息
  Future<AuthUser?> getProfile() async {
    if (_token == null) return null;
    final resp = await _get('profile');
    if (resp.ok) {
      _user = resp.user;
      await _save();
      return _user;
    }
    return null;
  }

  /// 退出登录
  Future<void> logout() async => _clear();
}