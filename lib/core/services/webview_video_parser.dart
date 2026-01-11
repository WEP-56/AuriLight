import 'dart:async';
import 'package:webview_flutter/webview_flutter.dart';

/// 基于WebView的视频URL解析器
/// 借鉴Kazumi的实现，通过WebView加载页面并注入JavaScript来提取视频URL
class WebViewVideoParser {
  /// Kazumi风格的视频解析脚本 - 拦截网络请求和Response
  static const String _kazumiVideoParserScript = '''
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
              window.flutter_inappwebview.callHandler('onVideoUrlFound', this.url);
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
              window.flutter_inappwebview.callHandler('onVideoUrlFound', args[1]);
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
                  window.flutter_inappwebview.callHandler('onVideoUrlFound', this.url);
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
                  window.flutter_inappwebview.callHandler('onVideoUrlFound', args[1]);
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

      // 5. 扫描现有的video标签 (备用方案)
      function scanVideoElements() {
        const videos = document.querySelectorAll('video');
        console.log('发现video标签数量: ' + videos.length);
        
        for (let video of videos) {
          let src = video.getAttribute('src');
          if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
            console.log('发现video源: ' + src);
            window.flutter_inappwebview.callHandler('onVideoUrlFound', src);
            return;
          }
          
          // 检查source标签
          const sources = video.getElementsByTagName('source');
          for (let source of sources) {
            src = source.getAttribute('src');
            if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
              console.log('发现source源: ' + src);
              window.flutter_inappwebview.callHandler('onVideoUrlFound', src);
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

  /// 解析视频URL
  static Future<String?> parseVideoUrl(String episodeUrl) async {
    final completer = Completer<String?>();
    WebViewController? controller;
    
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36')
        ..addJavaScriptChannel(
          'onVideoUrlFound',
          onMessageReceived: (JavaScriptMessage message) {
            final videoUrl = message.message;
            print('WebView发现视频URL: $videoUrl');
            
            if (!completer.isCompleted) {
              completer.complete(_cleanVideoUrl(videoUrl));
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) async {
              print('页面加载完成: $url');
              
              // 注入Kazumi风格的视频解析脚本
              try {
                await controller!.runJavaScript(_kazumiVideoParserScript);
                print('Kazumi视频解析脚本注入成功');
              } catch (e) {
                print('脚本注入失败: $e');
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
      print('开始加载页面: $episodeUrl');
      await controller.loadRequest(Uri.parse(episodeUrl));
      
      return await completer.future;
    } catch (e) {
      print('WebView解析失败: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    }
  }

  /// 清理视频URL
  static String _cleanVideoUrl(String url) {
    // 移除多余的斜杠，但保留协议部分的双斜杠
    String cleaned = url.replaceAllMapped(
      RegExp(r'([^:])//+'),
      (match) => '${match.group(1)}/',
    );
    
    // 确保协议部分正确
    if (cleaned.startsWith('http:/') && !cleaned.startsWith('http://')) {
      cleaned = cleaned.replaceFirst('http:/', 'http://');
    }
    if (cleaned.startsWith('https:/') && !cleaned.startsWith('https://')) {
      cleaned = cleaned.replaceFirst('https:/', 'https://');
    }
    
    return cleaned;
  }

  /// 检查URL是否为有效的视频流
  static bool isValidVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.m3u8', '.flv', '.avi', '.mkv', '.webm'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.contains(ext));
  }
}