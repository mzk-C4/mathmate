import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
  final int apkSizeBytes;
  final bool forceUpdate;
  final String apkSha256;

  AppVersion({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.apkSizeBytes,
    required this.forceUpdate,
    required this.apkSha256,
  });

  factory AppVersion.fromJson(Map<String, dynamic> json) {
    return AppVersion(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      apkUrl: json['apkUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
      apkSizeBytes: (json['apkSizeBytes'] as num?)?.toInt() ?? 0,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      apkSha256: json['apkSha256'] as String? ?? '',
    );
  }
}

/// 联网自动更新服务。
///
/// 启动时自动检查 mathmate.top/version.json，有新版本则弹窗提示更新。
/// Android 端支持下载 APK 后自动唤起安装器。
class UpdateService {
  static const String _versionUrl = 'https://mathmate.top/version.json';
  static const int _minimumApkBytes = 1024 * 1024;
  static const int _maximumApkBytes = 350 * 1024 * 1024;
  static const Set<String> _trustedDownloadHosts = {
    'mathmate.top',
    'www.mathmate.top',
  };

  /// 当前 APP 版本号（与 pubspec.yaml 保持同步）
  static const int currentBuildNumber = 2026071301;
  static const String currentVersion = '2.4.4';

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

      if (latest.version.trim().isEmpty ||
          latest.buildNumber <= 0 ||
          !_isTrustedDownloadUrl(latest.apkUrl)) {
        return null;
      }

      if (latest.forceUpdate || latest.buildNumber > currentBuildNumber) {
        return latest;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Android：下载 APK 到本地并唤起安装器。
  /// Web / 桌面：打开浏览器下载。
  static Future<String?> downloadAndInstall(
    AppVersion version, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_isTrustedDownloadUrl(version.apkUrl)) {
      return '下载失败：更新地址不可信';
    }

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // Web/桌面端 → 浏览器打开下载
      final url = Uri.parse(version.apkUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return null;
    }
    if (!Platform.isAndroid) return '自动安装目前仅支持 Android';

    if (_isDownloading) return '更新包正在下载，请勿重复操作';
    _isDownloading = true;

    http.Client? client;
    IOSink? sink;
    File? partialFile;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mathmate-${version.version}.apk');
      partialFile = File('${file.path}.part');
      if (await partialFile.exists()) await partialFile.delete();

      client = http.Client();
      final request = http.Request('GET', Uri.parse(version.apkUrl));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return '下载失败: HTTP ${response.statusCode}';
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        return '下载失败：服务器返回了网页而不是 APK';
      }

      final declaredLength = response.contentLength ?? version.apkSizeBytes;
      if (declaredLength > _maximumApkBytes) return '下载失败：安装包大小异常';

      sink = partialFile.openWrite();
      var received = 0;
      final signature = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > _maximumApkBytes) return '下载失败：安装包超过大小限制';
        if (signature.length < 4) {
          signature.addAll(chunk.take(4 - signature.length));
        }
        sink.add(chunk);
        if (declaredLength > 0) {
          onProgress?.call((received / declaredLength).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final isZip =
          signature.length == 4 &&
          signature[0] == 0x50 &&
          signature[1] == 0x4b &&
          signature[2] == 0x03 &&
          signature[3] == 0x04;
      if (!isZip || received < _minimumApkBytes) {
        return '下载失败：服务器返回的不是有效 APK';
      }
      if (version.apkSizeBytes > 0 && received != version.apkSizeBytes) {
        return '下载失败：安装包不完整，请重新下载';
      }
      if (version.apkSha256.trim().isNotEmpty) {
        final actualSha256 = (await sha256.bind(partialFile.openRead()).first)
            .toString();
        if (actualSha256.toLowerCase() !=
            version.apkSha256.trim().toLowerCase()) {
          return '下载失败：安装包完整性校验未通过';
        }
      }

      if (await file.exists()) await file.delete();
      await partialFile.rename(file.path);
      partialFile = null;
      onProgress?.call(1.0);

      // 唤起系统安装器
      final result = await OpenFile.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      return result.type == ResultType.done ? null : result.message;
    } catch (e) {
      return '下载失败: $e';
    } finally {
      await sink?.close();
      if (partialFile != null && await partialFile.exists()) {
        await partialFile.delete();
      }
      client?.close();
      _isDownloading = false;
    }
  }

  static bool _isTrustedDownloadUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        _trustedDownloadHosts.contains(uri.host.toLowerCase()) &&
        uri.path.toLowerCase().endsWith('.apk');
  }
}
