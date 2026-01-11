import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'webview_environment_manager.dart';

/// Windows WebView解析器 - 完全按照Kazumi的实现
/// 使用Kazumi定制的webview_windows包来支持Windows平台的WebView解析
class WindowsWebViewParser {
  /// 解析视频URL（Windows专用 - Kazumi风格）
  static Future<String?> parseVideoUrl(String episodeUrl, BuildContext context) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsWebViewParser只支持Windows平台');
    }

    try {
      print('[Windows WebView] 开始Kazumi风格解析: $episodeUrl');
      
      // 确保WebView环境已初始化
      final initialized = await WebViewEnvironmentManager.ensureInitialized();
      if (!initialized) {
        throw Exception('WebView环境初始化失败');
      }
      
      // 创建Kazumi风格的WebView解析器页面
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => _KazumiWindowsWebViewParserPage(episodeUrl: episodeUrl),
        ),
      );
      
      return result;
    } catch (e) {
      print('[Windows WebView] 解析失败: $e');
      return null;
    }
  }
}

/// Kazumi风格的Windows WebView解析页面
class _KazumiWindowsWebViewParserPage extends StatefulWidget {
  final String episodeUrl;

  const _KazumiWindowsWebViewParserPage({required this.episodeUrl});

  @override
  State<_KazumiWindowsWebViewParserPage> createState() => _KazumiWindowsWebViewParserPageState();
}

class _KazumiWindowsWebViewParserPageState extends State<_KazumiWindowsWebViewParserPage> {
  WebviewController? webviewController;
  String? foundVideoUrl;
  bool isLoading = true;
  Timer? timeoutTimer;
  String statusMessage = '正在初始化Kazumi WebView...';
  final List<StreamSubscription> subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initializeKazumiWebView();
  }

  @override
  void dispose() {
    timeoutTimer?.cancel();
    _cleanupWebView();
    super.dispose();
  }

  void _cleanupWebView() {
    for (final subscription in subscriptions) {
      try {
        subscription.cancel();
      } catch (_) {}
    }
    subscriptions.clear();
    
    if (webviewController != null) {
      try {
        webviewController!.executeScript('window.location.href = "about:blank";');
      } catch (_) {}
    }
  }

  void _initializeKazumiWebView() async {
    try {
      setState(() {
        statusMessage = '正在检查WebView环境...';
      });

      // 使用环境管理器确保初始化（避免重复初始化）
      final initialized = await WebViewEnvironmentManager.ensureInitialized();
      if (!initialized) {
        throw Exception('WebView环境初始化失败');
      }
      
      setState(() {
        statusMessage = '正在创建WebView控制器...';
      });

      // 创建WebView控制器（环境已经初始化过了）
      webviewController = WebviewController();
      await webviewController!.initialize();
      await webviewController!.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      
      setState(() {
        statusMessage = '正在设置视频源监听器...';
      });

      // 设置Kazumi风格的视频源监听器
      subscriptions.add(webviewController!.onM3USourceLoaded.listen((data) {
        final url = data['url'] ?? '';
        print('[Kazumi Windows WebView] 发现M3U8源: $url');
        if (url.isNotEmpty && foundVideoUrl == null) {
          _handleVideoUrlFound(url);
        }
      }));

      subscriptions.add(webviewController!.onVideoSourceLoaded.listen((data) {
        final url = data['url'] ?? '';
        print('[Kazumi Windows WebView] 发现视频源: $url');
        if (url.isNotEmpty && foundVideoUrl == null) {
          _handleVideoUrlFound(url);
        }
      }));

      setState(() {
        statusMessage = '正在加载页面...';
      });

      // 加载页面
      await webviewController!.loadUrl(widget.episodeUrl);
      
      setState(() {
        statusMessage = '正在解析视频源...';
        isLoading = false;
      });

      // 设置超时
      timeoutTimer = Timer(const Duration(seconds: 15), () {
        if (foundVideoUrl == null && mounted) {
          print('[Kazumi Windows WebView] 解析超时');
          Navigator.of(context).pop(null);
        }
      });
      
    } catch (e) {
      print('[Kazumi Windows WebView] 初始化失败: $e');
      setState(() {
        statusMessage = '初始化失败: $e';
        isLoading = false;
      });
      
      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop(null);
        }
      });
    }
  }

  void _handleVideoUrlFound(String videoUrl) {
    print('[Kazumi Windows WebView] 处理发现的视频URL: $videoUrl');
    
    if (foundVideoUrl != null) return;
    
    // 过滤无效URL
    if (_shouldSkipUrl(videoUrl)) {
      print('[Kazumi Windows WebView] 跳过无效URL: $videoUrl');
      return;
    }
    
    setState(() {
      foundVideoUrl = videoUrl;
      statusMessage = '找到视频源: ${videoUrl.length > 50 ? '${videoUrl.substring(0, 50)}...' : videoUrl}';
    });
    
    timeoutTimer?.cancel();
    
    // 延迟一下再返回，让用户看到成功信息
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop(videoUrl);
      }
    });
  }

  bool _shouldSkipUrl(String url) {
    if (url.length < 10) return true;
    
    final skipPatterns = [
      'javascript:',
      'void(0)',
      '.css',
      '.js',
      '.png',
      '.jpg',
      '.gif',
      '.ico',
      'data:',
      '#',
      'googleads',
      'googlesyndication.com',
      'prestrain.html',
      'prestrain%2Ehtml',
      'adtrafficquality',
      'about:blank',
    ];
    
    return skipPatterns.any((pattern) => url.contains(pattern));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频解析中'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // 隐藏返回按钮，防止用户中断解析
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // 隐藏的WebView容器 - 放在屏幕外或设为透明
            if (webviewController != null)
              Positioned(
                left: -2000, // 将WebView移到屏幕外，用户看不到但仍在运行
                top: -2000,
                width: 1920,
                height: 1080,
                child: Webview(webviewController!),
              ),
            // 自定义加载界面 - 用户看到的内容
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Kazumi风格的加载动画
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 状态文本
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: Column(
                      children: [
                        Text(
                          statusMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (foundVideoUrl != null) ...[
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '视频源解析成功！',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 解析提示
                  Text(
                    '正在从视频网站解析播放地址...',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请稍候，这可能需要几秒钟',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}