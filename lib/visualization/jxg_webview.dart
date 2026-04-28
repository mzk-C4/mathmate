import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mathmate/visualization/visualization_controller.dart';
import 'package:webview_flutter/webview_flutter.dart';

class JxgWebView extends StatefulWidget {
  final Map<String, dynamic> scene;
  final void Function(String message)? onEngineError;

  const JxgWebView({
    super.key,
    required this.scene,
    this.onEngineError,
  });

  @override
  State<JxgWebView> createState() => _JxgWebViewState();
}

class _JxgWebViewState extends State<JxgWebView> {
  final VisualizationController _visualizationController =
      VisualizationController();
  late final WebViewController _controller;
  bool _loading = true;
  bool _isDesktop = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _isDesktop = true;
      _loading = false;
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'GeometryBridge',
        onMessageReceived: (JavaScriptMessage message) {
          _onMessage(message.message);
        },
      )
      ..loadFlutterAsset('assets/visualization/index.html');
    _visualizationController.attach(_controller);
  }

  @override
  void didUpdateWidget(covariant JxgWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.scene, widget.scene)) {
      _visualizationController.loadScene(widget.scene);
    }
  }

  void _onMessage(String payload) {
    final dynamic parsed = jsonDecode(payload);
    if (parsed is! Map<String, dynamic>) {
      return;
    }

    final String? type = parsed['type'] as String?;
    if (type == 'renderReady') {
      _visualizationController.setReady(true);
      _visualizationController.loadScene(widget.scene);
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    if (type == 'error' && widget.onEngineError != null) {
      widget.onEngineError!(parsed['message'] as String? ?? 'Unknown error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.desktop_windows, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              '几何可视化暂不支持桌面端',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              '请在手机或平板上查看',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
