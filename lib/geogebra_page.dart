import 'package:flutter/material.dart';
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

  String get _title {
    switch (widget.appName) {
      case 'geometry':
      case 'classic':
        return '几何画板';
      case 'graphing':
        return '函数绘图';
      default:
        return '几何画板';
    }
  }

  Uri get _appUrl {
    switch (widget.appName) {
      case 'geometry':
      case 'classic':
        return Uri.parse('https://www.geogebra.org/geometry');
      case 'graphing':
        return Uri.parse('https://www.geogebra.org/calculator');
      default:
        return Uri.parse('https://www.geogebra.org/geometry');
    }
  }

  @override
  void initState() {
    super.initState();
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
      )
      ..loadRequest(_appUrl);
  }

  void _retry() {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    _controller.loadRequest(_appUrl);
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
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(color: Color(0xFF3F51B5)),
                  SizedBox(height: 12),
                  Text('加载中...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          if (_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, color: Colors.grey, size: 48),
                  const SizedBox(height: 16),
                  const Text('加载失败', style: TextStyle(fontSize: 16, color: Color(0xFF333333))),
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
