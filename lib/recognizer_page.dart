import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mathmate/beautiful_result_page.dart';
import 'package:mathmate/scanner/enhanced_crop_page.dart';
import 'package:mathmate/services/app_logger.dart';

class RecognizerPage extends StatefulWidget {
  const RecognizerPage({super.key});

  @override
  State<RecognizerPage> createState() => _RecognizerPageState();
}

class _RecognizerPageState extends State<RecognizerPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _image;

  Future<void> _processImage(ImageSource source) async {
    try {
      AppLogger.instance.info('[Recognizer] picking image from $source...');
      final XFile? selected = await _picker.pickImage(source: source);
      if (selected == null) {
        AppLogger.instance.info('[Recognizer] user cancelled pick');
        return;
      }
      AppLogger.instance.info('[Recognizer] picked: path=${selected.path}, name=${selected.name}');
      if (!mounted) return;

      if (!mounted) return;
      AppLogger.instance.info('[Recognizer] navigating to crop page...');
      final XFile? croppedFile = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (_) => EnhancedCropPage(imageFile: selected),
        ),
      );

      if (croppedFile == null) {
        AppLogger.instance.info('[Recognizer] crop cancelled');
        return;
      }
      if (!mounted) return;
      AppLogger.instance.info('[Recognizer] cropped: ${croppedFile.path}');

      setState(() {
        _image = XFile(croppedFile.path);
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BeautifulResultPage(image: croppedFile),
        ),
      );
    } catch (e, stack) {
      AppLogger.instance.error('[Recognizer] error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选取图片失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('公式识别插件'),
        backgroundColor: Colors.blue.withValues(alpha: 0.1),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: _image == null
                  ? const Center(child: Text('请上传或拍摄手写公式'))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: kIsWeb
                          ? Image.network(_image!.path, fit: BoxFit.contain)
                          : (kIsWeb
                              ? Image.network(_image!.path, fit: BoxFit.contain)
                              : Image.file(File(_image!.path), fit: BoxFit.contain)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _processImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _processImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('相册'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
