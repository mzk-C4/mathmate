import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;
  String? _localBasePath;

  String get _title {
    switch (widget.appName) {
      case 'geometry':
      case 'classic':
        return '几何画板';
      case 'graphing':
        return '函数绘图';
      case '3d':
        return '3D视图';
      case 'scientific':
        return '科学计算器';
      case 'suite':
        return '计算器套件';
      case 'probability':
        return '概率模型';
      default:
        return '几何画板';
    }
  }

  String get _htmlFile {
    switch (widget.appName) {
      case 'geometry':
      case 'classic':
        return 'geometry.html';
      case 'graphing':
        return 'graphing.html';
      case '3d':
        return '3d.html';
      case 'scientific':
        return 'scientific.html';
      case 'suite':
        return 'suite.html';
      case 'probability':
        return 'probability.html';
      default:
        return 'geometry.html';
    }
  }

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    try {
      _localBasePath = await _ensureLocalFiles();
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _hasError = true;
                });
              }
            },
          ),
        );
      await _controller.loadFile('$_localBasePath/$_htmlFile');
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
    if (mounted) setState(() {});
  }

  Future<String> _ensureLocalFiles() async {
    final Directory dir =
        Directory('${(await getApplicationDocumentsDirectory()).path}/geogebra');
    if (await dir.exists()) return dir.path;

    await dir.create(recursive: true);

    final String manifest =
        await rootBundle.loadString('assets/geogebra/file_manifest.txt');
    final List<String> files = manifest
        .split('\n')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    for (final String file in files) {
      final ByteData data = await rootBundle.load('assets/geogebra/$file');
      final File target = File('${dir.path}/$file');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(data.buffer.asUint8List());
    }
    return dir.path;
  }

  void _retry() {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    _controller.loadFile('$_localBasePath/$_htmlFile');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: <Widget>[
          if (_localBasePath != null) WebViewWidget(controller: _controller),
          if (_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('加载中...',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
          if (_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.error_outline,
                      color: cs.onSurface.withValues(alpha: 0.4), size: 48),
                  const SizedBox(height: 16),
                  Text('加载失败',
                      style: TextStyle(
                          fontSize: 16, color: cs.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
