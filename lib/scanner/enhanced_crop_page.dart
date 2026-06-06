import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class EnhancedCropPage extends StatefulWidget {
  final XFile imageFile;

  const EnhancedCropPage({super.key, required this.imageFile});

  @override
  State<EnhancedCropPage> createState() => _EnhancedCropPageState();
}

class _EnhancedCropPageState extends State<EnhancedCropPage> {
  // 裁剪框的四条边界（百分比 0.0 - 1.0）
  double _topPercent = 0.3;
  double _bottomPercent = 0.7;
  double _leftPercent = 0.1;
  double _rightPercent = 0.9;

  // 整体拖拽状态
  bool _isMovingBox = false;
  double _lastTouchDx = 0;
  double _lastTouchDy = 0;

  static const double _edgeThreshold = 0.04;

  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    widget.imageFile.readAsBytes().then((b) {
      if (mounted) setState(() => _imageBytes = b);
    }).catchError((_) {
      if (mounted) setState(() => _imageBytes = Uint8List(0));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('调整识别范围', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.blue),
            onPressed: _processCrop,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanStart: (details) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) return;
              final relativeX =
                  details.localPosition.dx / constraints.maxWidth;
              final relativeY =
                  details.localPosition.dy / constraints.maxHeight;

              final distTop = (relativeY - _topPercent).abs();
              final distBottom = (relativeY - _bottomPercent).abs();
              final distLeft = (relativeX - _leftPercent).abs();
              final distRight = (relativeX - _rightPercent).abs();

              final isInside = relativeX > _leftPercent &&
                  relativeX < _rightPercent &&
                  relativeY > _topPercent &&
                  relativeY < _bottomPercent;

              final isNearEdge = distTop < _edgeThreshold ||
                  distBottom < _edgeThreshold ||
                  distLeft < _edgeThreshold ||
                  distRight < _edgeThreshold;

              _isMovingBox = isInside && !isNearEdge;
              _lastTouchDx = relativeX;
              _lastTouchDy = relativeY;
            },
            onPanUpdate: (details) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) return;
              final relativeX =
                  details.localPosition.dx / constraints.maxWidth;
              final relativeY =
                  details.localPosition.dy / constraints.maxHeight;

              setState(() {
                if (_isMovingBox) {
                  final dx = relativeX - _lastTouchDx;
                  final dy = relativeY - _lastTouchDy;
                  final boxWidth = _rightPercent - _leftPercent;
                  final boxHeight = _bottomPercent - _topPercent;

                  double newLeft = _leftPercent + dx;
                  double newRight = _rightPercent + dx;
                  double newTop = _topPercent + dy;
                  double newBottom = _bottomPercent + dy;

                  if (newLeft < 0) {
                    newLeft = 0;
                    newRight = boxWidth;
                  }
                  if (newRight > 1) {
                    newRight = 1;
                    newLeft = 1 - boxWidth;
                  }
                  if (newTop < 0) {
                    newTop = 0;
                    newBottom = boxHeight;
                  }
                  if (newBottom > 1) {
                    newBottom = 1;
                    newTop = 1 - boxHeight;
                  }

                  _leftPercent = newLeft.clamp(0.0, 1.0);
                  _rightPercent = newRight.clamp(0.0, 1.0);
                  _topPercent = newTop.clamp(0.0, 1.0);
                  _bottomPercent = newBottom.clamp(0.0, 1.0);

                  _lastTouchDx = relativeX;
                  _lastTouchDy = relativeY;
                  return;
                }

                // 边缘拖拽（原有逻辑）
                final distTop = (relativeY - _topPercent).abs();
                final distBottom = (relativeY - _bottomPercent).abs();
                final distLeft = (relativeX - _leftPercent).abs();
                final distRight = (relativeX - _rightPercent).abs();

                final minDist = [
                  distTop,
                  distBottom,
                  distLeft,
                  distRight,
                ].reduce((a, b) => a < b ? a : b);

                if (minDist == distTop) {
                  _topPercent = relativeY.clamp(0.0, _bottomPercent);
                } else if (minDist == distBottom) {
                  _bottomPercent = relativeY.clamp(_topPercent, 1.0);
                } else if (minDist == distLeft) {
                  _leftPercent = relativeX.clamp(0.0, _rightPercent);
                } else if (minDist == distRight) {
                  _rightPercent = relativeX.clamp(_leftPercent, 1.0);
                }
              });
            },
            onPanEnd: (_) {
              _isMovingBox = false;
            },
            child: Stack(
              children: [
                // 1. 展示拍摄的原图
                Center(
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                      : const Center(child: CircularProgressIndicator()),
                ),
                // 2. 绘制矩形遮罩层
                Positioned.fill(
                  child: CustomPaint(
                    painter: CropOverlayPainter(
                      topPercent: _topPercent,
                      bottomPercent: _bottomPercent,
                      leftPercent: _leftPercent,
                      rightPercent: _rightPercent,
                    ),
                  ),
                ),
                // 3. 辅助手柄（上下）
                _buildHorizontalHandle(
                  constraints.maxHeight * _topPercent,
                  true,
                ),
                _buildHorizontalHandle(
                  constraints.maxHeight * _bottomPercent,
                  false,
                ),
                // 4. 辅助手柄（左右）
                _buildVerticalHandle(
                  constraints.maxWidth * _leftPercent,
                  true,
                ),
                _buildVerticalHandle(
                  constraints.maxWidth * _rightPercent,
                  false,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalHandle(double y, bool isTop) {
    return Positioned(
      top: y - 10,
      left: 0,
      right: 0,
      child: Container(
        height: 20,
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 60,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalHandle(double x, bool isLeft) {
    return Positioned(
      left: x - 10,
      top: 0,
      bottom: 0,
      child: Container(
        width: 20,
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // 利用 image 库进行像素级裁剪
  Future<void> _processCrop() async {
    try {
    final bytes = await widget.imageFile.readAsBytes();
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) return;

    final int x = (decodedImage.width * _leftPercent).toInt();
    final int y = (decodedImage.height * _topPercent).toInt();
    final int width =
        (decodedImage.width * (_rightPercent - _leftPercent)).toInt();
    final int height =
        (decodedImage.height * (_bottomPercent - _topPercent)).toInt();

    final croppedImage = img.copyCrop(
      decodedImage,
      x: x,
      y: y,
      width: width,
      height: height,
    );

    // 保存到文件再返回，避免 Navigator pop 丢失 in-memory bytes
    final croppedBytes = Uint8List.fromList(img.encodeJpg(croppedImage));
    final String srcPath = widget.imageFile.path;
    final String outPath = '${srcPath.substring(0, srcPath.lastIndexOf('.'))}_cropped.jpg';
    File(outPath).writeAsBytesSync(croppedBytes);
    final croppedFile = XFile(outPath, bytes: croppedBytes);

    if (mounted) Navigator.pop(context, croppedFile);
    } catch (e) {
      debugPrint('_processCrop error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失败: $e')),
        );
      }
    }
  }
}

// 矩形遮罩绘制器
class CropOverlayPainter extends CustomPainter {
  final double topPercent;
  final double bottomPercent;
  final double leftPercent;
  final double rightPercent;

  CropOverlayPainter({
    required this.topPercent,
    required this.bottomPercent,
    required this.leftPercent,
    required this.rightPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final topY = size.height * topPercent;
    final bottomY = size.height * bottomPercent;
    final leftX = size.width * leftPercent;
    final rightX = size.width * rightPercent;

    // 绘制上方阴影
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, topY), paint);
    // 绘制下方阴影
    canvas.drawRect(Rect.fromLTRB(0, bottomY, size.width, size.height), paint);
    // 绘制左侧阴影
    canvas.drawRect(Rect.fromLTRB(0, topY, leftX, bottomY), paint);
    // 绘制右侧阴影
    canvas.drawRect(Rect.fromLTRB(rightX, topY, size.width, bottomY), paint);

    // 绘制中间的矩形高亮框
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(
      Rect.fromLTRB(leftX, topY, rightX, bottomY),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(CropOverlayPainter oldDelegate) => true;
}
