import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerService {
  final ImagePicker _picker = ImagePicker();

  Future<dynamic> startScanning(BuildContext context) async {
    if (kIsWeb) {
      try {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 90,
        );
        if (photo != null) return photo;
      } catch (e) {
        debugPrint('ScannerService web pickImage error: $e');
      }
      return null;
    }

    if (!context.mounted) return null;

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      debugPrint('ScannerService: camera permission denied.');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相机权限才能拍照')),
        );
      }
      return null;
    }

    if (!context.mounted) return null;

    final ImageSource? source = await _showSourcePicker(context);
    if (source == null) {
      debugPrint('ScannerService: user cancelled source selection.');
      return null;
    }

    if (!context.mounted) return null;

    XFile? photo;
    try {
      photo = await _picker.pickImage(source: source, imageQuality: 90);
    } catch (e) {
      debugPrint('ScannerService: pickImage error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取图片失败: $e')),
        );
      }
      return null;
    }

    if (photo == null) {
      debugPrint('ScannerService: user cancelled taking photo.');
      return null;
    }

    if (!context.mounted) return null;

    // 直接返回 XFile，跨平台兼容
    return photo;
  }

  Future<ImageSource?> _showSourcePicker(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final ColorScheme cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '选择图片来源',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: cs.primary,
                    ),
                  ),
                  title: Text('拍照', style: TextStyle(color: cs.onSurface)),
                  subtitle: Text('使用相机拍摄题目', style: TextStyle(color: cs.onSurfaceVariant)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: cs.primary,
                    ),
                  ),
                  title: Text('从相册选择', style: TextStyle(color: cs.onSurface)),
                  subtitle: Text('从相册中选取图片', style: TextStyle(color: cs.onSurfaceVariant)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}