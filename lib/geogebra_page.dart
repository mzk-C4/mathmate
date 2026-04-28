import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mathmate/services/local_geogebra_server.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final LocalGeogebraServer _server = LocalGeogebraServer();
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _isDesktop = false;

  String get _externalUrl {
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
    _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (_isDesktop) {
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openExternal());
    } else {
      _initWebView();
    }
  }

  Future<void> _openExternal() async {
    final Uri uri = Uri.parse(_externalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _initWebView() async {
    try {
      final String baseUrl = await _server.start();
      final String url = '$baseUrl?appName=${widget.appName}';

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _loading = false;
                  _error = '加载失败: ${error.description}';
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(url));

      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '启动失败: $e';
        });
      }
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isDesktop) {
      return Center(
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
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('打开 GeoGebra'),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _error = null;
                  _loading = true;
                });
                _initWebView();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: <Widget>[
        if (_controller != null) WebViewWidget(controller: _controller!),
        if (_loading)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(color: Color(0xFF3F51B5)),
                SizedBox(height: 12),
                Text('GeoGebra 加载中...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
      ],
    );
  }
}
