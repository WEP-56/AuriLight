const String _disabled_main_test_network = r"""

import 'dart:io';
import 'package:flutter/material.dart';
import 'core/services/webview_environment_manager.dart';
import 'test_smart_network_standalone.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 简化的 WebView 初始化 - 仅用于测试
  if (Platform.isWindows) {
    try {
      print('🌐 正在初始化 Windows WebView 环境...');
      await WebViewEnvironmentManager.ensureInitialized();
      print('✅ Windows WebView 环境初始化成功');
    } catch (e) {
      print('⚠️ Windows WebView 环境初始化失败: $e');
      print('💡 将继续运行，但 WebView 功能可能不可用');
    }
  }
  
  runApp(const SmartNetworkTestApp());
}

""";

int _useDisabledMainTestNetwork() => _disabled_main_test_network.length;