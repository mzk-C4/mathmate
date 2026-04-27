import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class GeogebraPage extends StatefulWidget {
  final String appName;

  const GeogebraPage({
    super.key,
    this.appName = 'graphing',
  });

  @override
  State<GeogebraPage> createState() => _GeogebraPageState();
}

class _GeogebraPageState extends State<GeogebraPage> {
  bool _launched = false;

  String get _url {
    switch (widget.appName) {
      case 'classic':
        return 'https://www.geogebra.org/classic';
      case '3d':
        return 'https://www.geogebra.org/3d';
      case 'geometry':
        return 'https://www.geogebra.org/geometry';
      default:
        return 'https://www.geogebra.org/graphing';
    }
  }

  String get _title {
    switch (widget.appName) {
      case 'classic':
        return '几何画板';
      case '3d':
        return '3D 绘图';
      case 'geometry':
        return '平面几何';
      default:
        return '函数绘图';
    }
  }

  @override
  void initState() {
    super.initState();
    _openGeoGebra();
  }

  Future<void> _openGeoGebra() async {
    if (_launched) return;
    _launched = true;

    final Uri uri = Uri.parse(_url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.launch, size: 56, color: Color(0xFF3F51B5)),
            const SizedBox(height: 20),
            const Text(
              '正在打开 GeoGebra...',
              style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
            ),
            const SizedBox(height: 8),
            const Text(
              '如未自动打开，请点击下方按钮',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openGeoGebra,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开 GeoGebra'),
            ),
          ],
        ),
      ),
    );
  }
}
