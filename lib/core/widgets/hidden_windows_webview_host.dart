import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../services/smart_network_service_v2.dart';
import '../services/webview_environment_manager.dart';

class HiddenWindowsWebViewHost extends StatefulWidget {
  final Widget child;

  const HiddenWindowsWebViewHost({super.key, required this.child});

  @override
  State<HiddenWindowsWebViewHost> createState() => _HiddenWindowsWebViewHostState();
}

class _HiddenWindowsWebViewHostState extends State<HiddenWindowsWebViewHost> {
  WebviewController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!Platform.isWindows) return;

    try {
      debugPrint('🧩 HiddenWindowsWebViewHost: 初始化 WebView 宿主...');
      final initialized = await WebViewEnvironmentManager.ensureInitialized();
      if (!initialized) return;

      final controller = WebviewController();
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      SmartNetworkServiceV2().attachWebViewController(controller);
      debugPrint('🧩 HiddenWindowsWebViewHost: WebView 宿主就绪');

      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (_) {
      // Ignore: WebView host is best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        if (_controller != null)
          Positioned(
            left: -2000,
            top: -2000,
            width: 1920,
            height: 1080,
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(
                opacity: 0,
                child: Webview(_controller!),
              ),
            ),
          ),
      ],
    );
  }
}
