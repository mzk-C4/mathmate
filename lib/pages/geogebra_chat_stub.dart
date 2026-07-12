import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 移动端 GeoGebra 聊天页面 — 通过 WebView 加载服务器上的 chat-with-geogebra。
class GeogebraChatPage extends StatefulWidget {
  const GeogebraChatPage({super.key});

  @override
  State<GeogebraChatPage> createState() => _GeogebraChatPageState();
}

class _GeogebraChatPageState extends State<GeogebraChatPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://mathmate.top/geogebra-chat/'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoGebra 对话绘图'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
