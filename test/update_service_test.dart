import 'package:flutter_test/flutter_test.dart';
import 'package:mathmate/services/update_service.dart';

void main() {
  group('AppVersion metadata', () {
    test('accepts a complete signed APK manifest', () {
      final version = AppVersion.fromJson(<String, dynamic>{
        'version': '2.4.4',
        'buildNumber': 2026071303,
        'apkUrl': 'https://mathmate.top/app/mathmate-2.4.4.apk',
        'releaseNotes': 'Update',
        'apkSizeBytes': 120 * 1024 * 1024,
        'forceUpdate': false,
        'apkSha256': 'a' * 64,
      });

      expect(version.hasValidMetadata, isTrue);
    });

    test('rejects manifests without a SHA-256 checksum', () {
      final version = AppVersion.fromJson(<String, dynamic>{
        'version': '2.4.4',
        'buildNumber': 2026071303,
        'apkUrl': 'https://mathmate.top/app/mathmate-2.4.4.apk',
        'releaseNotes': 'Update',
        'apkSizeBytes': 120 * 1024 * 1024,
        'forceUpdate': false,
        'apkSha256': '',
      });

      expect(version.hasValidMetadata, isFalse);
    });

    test('rejects unsafe version text used in the local APK filename', () {
      final version = AppVersion.fromJson(<String, dynamic>{
        'version': '../../payload',
        'buildNumber': 2026071303,
        'apkUrl': 'https://mathmate.top/app/mathmate.apk',
        'releaseNotes': 'Update',
        'apkSizeBytes': 120 * 1024 * 1024,
        'forceUpdate': false,
        'apkSha256': 'b' * 64,
      });

      expect(version.hasValidMetadata, isFalse);
    });
  });
}
