import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 简化的WebView视频解析器
/// 专门用于解决平台初始化问题
class SimpleWebViewParser {
  /// 解析视频URL（需要传入context）
  static Future<String?> parseVideoUrl(String episodeUrl, BuildContext context) async {
    try {
      // 检查平台支持
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        print('桌面平台不支持WebView解析');
        return null;
      }
      
      print('开始WebView解析: $episodeUrl');
      
      // 创建一个简单的WebView widget来处理解析
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => _WebViewParserPage(episodeUrl: episodeUrl),
        ),
      );
      
      return result;
    } catch (e) {
      print('WebView解析失败: $e');
      return null;
    }
  }
  
  /// 无UI的WebView解析（直接使用WebViewController）
  static Future<String?> parseVideoUrlHeadless(String episodeUrl) async {
    try {
      // 检查平台支持
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        print('桌面平台不支持WebView解析');
        return null;
      }
      
      print('开始无头WebView解析: $episodeUrl');
      
      final Completer<String?> completer = Completer<String?>();
      late WebViewController controller;
      
      // 创建WebView控制器
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36')
        ..addJavaScriptChannel(
          'VideoUrlFound',
          onMessageReceived: (JavaScriptMessage message) {
            final videoUrl = message.message;
            print('WebView发现视频URL: $videoUrl');
            
            if (!completer.isCompleted) {
              completer.complete(videoUrl);
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) async {
              print('页面加载完成: $url');
              
              // 注入视频解析脚本
              try {
                await controller.runJavaScript(_getVideoParserScript());
                print('视频解析脚本注入成功');
              } catch (e) {
                print('脚本注入失败: $e');
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              }
              
              // 设置超时
              Timer(const Duration(seconds: 15), () {
                if (!completer.isCompleted) {
                  print('视频解析超时');
                  completer.complete(null);
                }
              });
            },
            onWebResourceError: (WebResourceError error) {
              print('WebView错误: ${error.description}');
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            },
          ),
        );

      // 加载页面
      await controller.loadRequest(Uri.parse(episodeUrl));
      
      return await completer.future;
    } catch (e) {
      print('无头WebView解析失败: $e');
      return null;
    }
  }
  
  /// 获取视频解析脚本（Kazumi风格的完整解析逻辑）
  static String _getVideoParserScript() {
    return '''
      (function() {
        console.log('Kazumi视频解析脚本已加载: ' + window.location.href);
        
        // 1. 拦截Response.text()方法来捕获M3U8内容 (Kazumi核心逻辑)
        const _r_text = window.Response.prototype.text;
        window.Response.prototype.text = function () {
          return new Promise((resolve, reject) => {
            _r_text.call(this).then((text) => {
              resolve(text);
              if (text.trim().startsWith("#EXTM3U")) {
                console.log('发现M3U8源: ' + this.url);
                VideoUrlFound.postMessage(this.url);
              }
            }).catch(reject);
          });
        }

        // 2. 拦截XMLHttpRequest来捕获视频请求 (Kazumi核心逻辑)
        const _open = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function (...args) {
          this.addEventListener("load", () => {
            try {
              let content = this.responseText;
              if (content && content.trim().startsWith("#EXTM3U") && args[1] !== null && args[1] !== undefined) {
                console.log('XHR发现M3U8源: ' + args[1]);
                VideoUrlFound.postMessage(args[1]);
              }
            } catch(e) {
              console.log('XHR解析错误: ' + e);
            }
          });
          return _open.apply(this, args);
        }
        
        // 3. iframe注入逻辑 (Kazumi特色功能)
        function injectIntoIframe(iframe) {
          try {
            const iframeWindow = iframe.contentWindow;
            if (!iframeWindow) return;
            
            const iframe_r_text = iframeWindow.Response.prototype.text;
            iframeWindow.Response.prototype.text = function () {
              return new Promise((resolve, reject) => {
                iframe_r_text.call(this).then((text) => {
                  resolve(text);
                  if (text.trim().startsWith("#EXTM3U")) {
                    console.log('iframe发现M3U8源: ' + this.url);
                    VideoUrlFound.postMessage(this.url);
                  }
                }).catch(reject);
              });
            }
            
            const iframe_open = iframeWindow.XMLHttpRequest.prototype.open;
            iframeWindow.XMLHttpRequest.prototype.open = function (...args) {
              this.addEventListener("load", () => {
                try {
                  let content = this.responseText;
                  if (content && content.trim().startsWith("#EXTM3U") && args[1] !== null && args[1] !== undefined) {
                    console.log('iframe XHR发现M3U8源: ' + args[1]);
                    VideoUrlFound.postMessage(args[1]);
                  }
                } catch(e) {
                  console.log('iframe XHR解析错误: ' + e);
                }
              });
              return iframe_open.apply(this, args);
            }
          } catch (e) {
            console.error('iframe注入失败:', e);
          }
        }

        // 4. 设置iframe监听器
        function setupIframeListeners() {
          document.querySelectorAll('iframe').forEach(iframe => {
            if (iframe.contentDocument) {
              injectIntoIframe(iframe);
            }
            iframe.addEventListener('load', () => injectIntoIframe(iframe));
          });
          
          const observer = new MutationObserver(mutations => {
            mutations.forEach(mutation => {
              if (mutation.type === 'childList') {
                mutation.addedNodes.forEach(node => {
                  if (node.nodeName === 'IFRAME') {
                    node.addEventListener('load', () => injectIntoIframe(node));
                  }
                  if (node.querySelectorAll) {
                    node.querySelectorAll('iframe').forEach(iframe => {
                      iframe.addEventListener('load', () => injectIntoIframe(iframe));
                    });
                  }
                });
              }
            });
          });
          
          observer.observe(document.body, { childList: true, subtree: true });
        }
        
        // 5. 扫描现有的video标签
        function scanVideoElements() {
          const videos = document.querySelectorAll('video');
          console.log('发现video标签数量: ' + videos.length);
          
          for (let video of videos) {
            let src = video.getAttribute('src');
            if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
              console.log('发现video源: ' + src);
              VideoUrlFound.postMessage(src);
              return;
            }
            
            const sources = video.getElementsByTagName('source');
            for (let source of sources) {
              src = source.getAttribute('src');
              if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
                console.log('发现source源: ' + src);
                VideoUrlFound.postMessage(src);
                return;
              }
            }
          }
        }
        
        // 6. 监听DOM变化
        const observer = new MutationObserver((mutations) => {
          mutations.forEach(mutation => {
            if (mutation.type === 'attributes' && mutation.target.nodeName === 'VIDEO') {
              scanVideoElements();
            }
            mutation.addedNodes.forEach(node => {
              if (node.nodeName === 'VIDEO') {
                scanVideoElements();
              }
              if (node.querySelectorAll) {
                const videos = node.querySelectorAll('video');
                if (videos.length > 0) {
                  scanVideoElements();
                }
              }
            });
          });
        });
        
        observer.observe(document.body, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src']
        });
        
        // 7. 初始化
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', () => {
            setupIframeListeners();
            scanVideoElements();
          });
        } else {
          setupIframeListeners();
          scanVideoElements();
        }
        
        // 8. 定时扫描（防止动态加载的内容）
        setTimeout(() => {
          setupIframeListeners();
          scanVideoElements();
        }, 1000);
        setTimeout(() => {
          setupIframeListeners();
          scanVideoElements();
        }, 3000);
        setTimeout(() => {
          setupIframeListeners();
          scanVideoElements();
        }, 5000);
        
        console.log('Kazumi视频解析脚本初始化完成');
      })();
    ''';
  }
}

/// WebView解析页面
class _WebViewParserPage extends StatefulWidget {
  final String episodeUrl;

  const _WebViewParserPage({required this.episodeUrl});

  @override
  State<_WebViewParserPage> createState() => _WebViewParserPageState();
}

class _WebViewParserPageState extends State<_WebViewParserPage> {
  late WebViewController controller;
  String? foundVideoUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36')
      ..addJavaScriptChannel(
        'VideoUrlFound',
        onMessageReceived: (JavaScriptMessage message) {
          final videoUrl = message.message;
          print('WebView发现视频URL: $videoUrl');
          
          if (foundVideoUrl == null) {
            setState(() {
              foundVideoUrl = videoUrl;
            });
            // 返回结果
            Navigator.of(context).pop(videoUrl);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            print('页面加载完成: $url');
            setState(() {
              isLoading = false;
            });
            
            // 注入视频解析脚本
            try {
              await controller.runJavaScript(_getVideoParserScript());
              print('视频解析脚本注入成功');
            } catch (e) {
              print('脚本注入失败: $e');
            }
            
            // 设置超时
            Timer(const Duration(seconds: 15), () {
              if (foundVideoUrl == null && mounted) {
                print('视频解析超时');
                Navigator.of(context).pop(null);
              }
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('WebView错误: ${error.description}');
            if (mounted) {
              Navigator.of(context).pop(null);
            }
          },
        ),
      );

    // 加载页面
    controller.loadRequest(Uri.parse(widget.episodeUrl));
  }

  String _getVideoParserScript() {
    return '''
      (function() {
        console.log('视频解析脚本已加载: ' + window.location.href);
        
        // 拦截Response.text()方法来捕获M3U8内容
        const _r_text = window.Response.prototype.text;
        window.Response.prototype.text = function () {
          return new Promise((resolve, reject) => {
            _r_text.call(this).then((text) => {
              resolve(text);
              if (text.trim().startsWith("#EXTM3U")) {
                console.log('发现M3U8源: ' + this.url);
                VideoUrlFound.postMessage(this.url);
              }
            }).catch(reject);
          });
        }

        // 拦截XMLHttpRequest来捕获视频请求
        const _open = window.XMLHttpRequest.prototype.open;
        window.XMLHttpRequest.prototype.open = function (...args) {
          this.addEventListener("load", () => {
            try {
              let content = this.responseText;
              if (content && content.trim().startsWith("#EXTM3U") && args[1] !== null && args[1] !== undefined) {
                console.log('XHR发现M3U8源: ' + args[1]);
                VideoUrlFound.postMessage(args[1]);
              }
            } catch(e) {
              console.log('XHR解析错误: ' + e);
            }
          });
          return _open.apply(this, args);
        }
        
        // 扫描现有的video标签
        function scanVideoElements() {
          const videos = document.querySelectorAll('video');
          console.log('发现video标签数量: ' + videos.length);
          
          for (let video of videos) {
            let src = video.getAttribute('src');
            if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
              console.log('发现video源: ' + src);
              VideoUrlFound.postMessage(src);
              return;
            }
            
            const sources = video.getElementsByTagName('source');
            for (let source of sources) {
              src = source.getAttribute('src');
              if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
                console.log('发现source源: ' + src);
                VideoUrlFound.postMessage(src);
                return;
              }
            }
          }
        }
        
        // 立即扫描
        scanVideoElements();
        
        // 定时扫描
        setTimeout(scanVideoElements, 1000);
        setTimeout(scanVideoElements, 3000);
        setTimeout(scanVideoElements, 5000);
        
        console.log('视频解析脚本初始化完成');
      })();
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频解析中...'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在解析视频源...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}