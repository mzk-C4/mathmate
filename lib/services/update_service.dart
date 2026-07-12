import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// 版本信息模型
class AppVersion {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;

  AppVersion({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      apkUrl: json['apkUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }
}

/// 联网自动更新服务。
///
/// 启动时自动检查 mathmate.top/version.json，有新版本则弹窗提示更新。
/// Android 端支持下载 APK 后自动唤起安装器。
class UpdateService {
  static const String _versionUrl = 'https://mathmate.top/version.json';

  /// 当前 APP 版本号（与 pubspec.yaml 保持同步）
  static const int currentBuildNumber = 20260712;
  static const String currentVersion = '2.4.3';

  /// 是否正在下载
  static bool _isDownloading = false;

  /// 检查更新。返回最新版本信息，若已是最新则返回 null。
  static Future<AppVersion?> checkUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = AppVersion.fromJson(json);

      if (latest.buildNumber > currentBuildNumber) {
        return latest;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Android：下载 APK 到本地并唤起安装器。
  /// Web / 桌面：打开浏览器下载。
  static Future<String?> downloadAndInstall(AppVersion version,
      {void Function(double progress)? onProgress}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      // Web/桌面端 → 浏览器打开下载
      final url = Uri.parse(version.apkUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return null;
    }

    if (_isDownloading) return null;
    _isDownloading = true;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mathmate-${version.version}.apk');

      final response = await http.get(Uri.parse(version.apkUrl));
      if (response.statusCode != 200) return '下载失败: HTTP ${response.statusCode}';

      await file.writeAsBytes(response.bodyBytes);

      // 唤起系统安装器
      final result = await OpenFile.open(file.path,
          type: 'application/vnd.android.package-archive');
      return result.message;
    } catch (e) {
      return '下载失败: $e';
    } finally {
      _isDownloading = false;
    }
  }
}
