import 'dart:io';
import 'package:webview_windows/webview_windows.dart';

/// WebView环境管理器 - 防止重复初始化
/// 完全按照Kazumi的实现来管理WebView环境
class WebViewEnvironmentManager {
  static bool _isInitialized = false;
  static bool _isInitializing = false;
  
  /// 确保WebView环境已初始化（单例模式）
  static Future<bool> ensureInitialized() async {
    if (_isInitialized) {
      print('[WebView Manager] 环境已初始化，跳过');
      return true;
    }
    
    if (_isInitializing) {
      print('[WebView Manager] 正在初始化中，等待完成...');
      // 等待初始化完成
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    if (!Platform.isWindows) {
      print('[WebView Manager] 非Windows平台，无需初始化webview_windows');
      _isInitialized = true;
      return true;
    }
    
    try {
      print('[WebView Manager] 开始初始化Windows WebView环境...');
      _isInitializing = true;
      
      await WebviewController.initializeEnvironment();
      
      _isInitialized = true;
      _isInitializing = false;
      
      print('[WebView Manager] Windows WebView环境初始化成功');
      return true;
    } catch (e) {
      _isInitializing = false;
      
      if (e.toString().contains('environment_already_initialized')) {
        print('[WebView Manager] 环境已经初始化过了，标记为成功');
        _isInitialized = true;
        return true;
      }
      
      print('[WebView Manager] WebView环境初始化失败: $e');
      return false;
    }
  }
  
  /// 重置初始化状态（用于测试或重新初始化）
  static void reset() {
    _isInitialized = false;
    _isInitializing = false;
    print('[WebView Manager] 重置初始化状态');
  }
  
  /// 检查是否已初始化
  static bool get isInitialized => _isInitialized;
}