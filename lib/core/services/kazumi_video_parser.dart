import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'windows_webview_parser.dart';

/// Kazumi风格的视频URL解析结果
class KazumiVideoParseResult {
  final String? videoUrl;
  final Map<String, String> httpHeaders;
  final String? referer;
  final bool isSuccess;
  final String? errorMessage;

  KazumiVideoParseResult({
    this.videoUrl,
    this.httpHeaders = const {},
    this.referer,
    this.isSuccess = false,
    this.errorMessage,
  });

  factory KazumiVideoParseResult.success(String videoUrl, Map<String, String> headers, {String? referer}) {
    return KazumiVideoParseResult(
      videoUrl: videoUrl,
      httpHeaders: headers,
      referer: referer,
      isSuccess: true,
    );
  }

  factory KazumiVideoParseResult.failure(String error) {
    return KazumiVideoParseResult(
      isSuccess: false,
      errorMessage: error,
    );
  }
}

/// Kazumi风格的规则配置
class KazumiRuleConfig {
  final bool useWebview;
  final bool useNativePlayer;
  final bool useLegacyParser;
  final bool adBlocker;
  final String userAgent;
  final String referer;
  final String baseURL;

  KazumiRuleConfig({
    this.useWebview = false,
    this.useNativePlayer = true,
    this.useLegacyParser = false,
    this.adBlocker = false,
    this.userAgent = '',
    this.referer = '',
    this.baseURL = '',
  });

  factory KazumiRuleConfig.fromJson(Map<String, dynamic> json) {
    return KazumiRuleConfig(
      useWebview: json['useWebview'] ?? false,
      useNativePlayer: json['useNativePlayer'] ?? true,
      useLegacyParser: json['useLegacyParser'] ?? false,
      adBlocker: json['adBlocker'] ?? false,
      userAgent: json['userAgent'] ?? '',
      referer: json['referer'] ?? '',
      baseURL: json['baseURL'] ?? '',
    );
  }
}

/// Kazumi风格的完整视频解析器
class KazumiVideoParser {
  static final Dio _dio = Dio();
  static const int _parseTimeout = 15; // 15秒超时
  static const int _maxRecursionDepth = 2; // 最大递归深度

  /// 主要解析入口 - 完全按照Kazumi的逻辑
  static Future<KazumiVideoParseResult> parseVideoUrl(
    String episodeUrl, 
    KazumiRuleConfig config,
    {BuildContext? context}
  ) async {
    try {
      print('[Kazumi Parser] 开始解析: $episodeUrl');
      print('[Kazumi Parser] 规则配置: useWebview=${config.useWebview}, useNativePlayer=${config.useNativePlayer}');

      // 1. 检查是否为直接视频URL
      if (_isDirectVideoUrl(episodeUrl)) {
        final headers = _generateHttpHeaders(episodeUrl, episodeUrl, config);
        return KazumiVideoParseResult.success(episodeUrl, headers);
      }

      // 2. 根据规则选择解析方式
      if (config.useWebview) {
        print('[Kazumi Parser] 使用WebView解析');
        
        if (context != null) {
          return await _parseWithWebView(episodeUrl, config, context);
        } else {
          print('[Kazumi Parser] 无Context，回退到HTML解析');
          return await _parseWithHtml(episodeUrl, config);
        }
      } else {
        print('[Kazumi Parser] 使用HTML解析');
        return await _parseWithHtml(episodeUrl, config);
      }
    } catch (e) {
      print('[Kazumi Parser] 解析失败: $e');
      return KazumiVideoParseResult.failure('解析失败: $e');
    }
  }

  /// WebView解析 - 完全按照Kazumi的实现
  static Future<KazumiVideoParseResult> _parseWithWebView(
    String episodeUrl, 
    KazumiRuleConfig config, 
    BuildContext context
  ) async {
    try {
      print('[Kazumi Parser] 开始WebView解析');
      
      String? result;
      
      // 根据平台选择不同的WebView实现
      if (Platform.isWindows) {
        print('[Kazumi Parser] 使用Windows WebView解析');
        result = await WindowsWebViewParser.parseVideoUrl(episodeUrl, context);
      } else {
        print('[Kazumi Parser] 使用标准WebView解析');
        // 创建标准WebView解析器
        result = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => _KazumiWebViewParser(
              episodeUrl: episodeUrl,
              config: config,
            ),
          ),
        );
      }

      if (result != null && result.isNotEmpty) {
        final decodedUrl = _decodeVideoSource(result);
        final headers = _generateHttpHeaders(decodedUrl, episodeUrl, config);
        return KazumiVideoParseResult.success(decodedUrl, headers, referer: episodeUrl);
      }

      print('[Kazumi Parser] WebView解析未找到视频URL，回退到HTML解析');
      return await _parseWithHtml(episodeUrl, config);
    } catch (e) {
      print('[Kazumi Parser] WebView解析失败: $e，回退到HTML解析');
      return await _parseWithHtml(episodeUrl, config);
    }
  }

  /// HTML解析 - 完全按照Kazumi的实现
  static Future<KazumiVideoParseResult> _parseWithHtml(
    String episodeUrl, 
    KazumiRuleConfig config,
    {int depth = 0}
  ) async {
    if (depth > _maxRecursionDepth) {
      return KazumiVideoParseResult.failure('递归深度超限');
    }

    try {
      print('[Kazumi Parser] HTML解析 - 深度: $depth, URL: $episodeUrl');
      
      // 生成请求头
      final headers = _generateHttpHeaders(episodeUrl, episodeUrl, config);
      
      // 发送HTTP请求
      final response = await _dio.get(
        episodeUrl,
        options: Options(
          headers: headers,
          followRedirects: true,
          validateStatus: (status) => status! < 500,
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
        ),
      );

      print('[Kazumi Parser] 页面响应: ${response.statusCode}, 长度: ${response.data.toString().length}');
      
      final document = html_parser.parse(response.data);
      
      // 按照Kazumi的顺序尝试提取视频URL
      String? videoUrl = await _extractVideoUrlFromHtml(document, episodeUrl, config, depth);
      
      if (videoUrl != null) {
        // 处理相对URL
        videoUrl = _resolveUrl(videoUrl, episodeUrl);
        
        // 解码视频源
        final decodedUrl = _decodeVideoSource(videoUrl);
        
        if (_isDirectVideoUrl(decodedUrl)) {
          final videoHeaders = _generateHttpHeaders(decodedUrl, episodeUrl, config);
          return KazumiVideoParseResult.success(decodedUrl, videoHeaders, referer: episodeUrl);
        } else if (decodedUrl != episodeUrl && depth < _maxRecursionDepth) {
          // 递归解析
          print('[Kazumi Parser] 递归解析: $decodedUrl');
          return await _parseWithHtml(decodedUrl, config, depth: depth + 1);
        }
      }

      return KazumiVideoParseResult.failure('未找到视频URL');
    } catch (e) {
      print('[Kazumi Parser] HTML解析失败: $e');
      return KazumiVideoParseResult.failure('HTML解析失败: $e');
    }
  }

  /// 从HTML中提取视频URL - 完全按照Kazumi的逻辑
  static Future<String?> _extractVideoUrlFromHtml(
    html_dom.Document document, 
    String pageUrl, 
    KazumiRuleConfig config,
    int depth
  ) async {
    print('[Kazumi Parser] 开始从HTML提取视频URL');

    // 1. 查找video标签
    final videoElements = document.querySelectorAll('video');
    print('[Kazumi Parser] 发现video标签: ${videoElements.length}个');
    for (final video in videoElements) {
      final src = video.attributes['src'];
      if (src != null && src.isNotEmpty && _isDirectVideoUrl(src)) {
        print('[Kazumi Parser] 从video标签找到: $src');
        return src;
      }
    }

    // 2. 查找source标签
    final sourceElements = document.querySelectorAll('source');
    print('[Kazumi Parser] 发现source标签: ${sourceElements.length}个');
    for (final source in sourceElements) {
      final src = source.attributes['src'];
      if (src != null && src.isNotEmpty && _isDirectVideoUrl(src)) {
        print('[Kazumi Parser] 从source标签找到: $src');
        return src;
      }
    }

    // 3. 查找iframe标签（Kazumi的iframe处理逻辑）
    final iframeElements = document.querySelectorAll('iframe');
    print('[Kazumi Parser] 发现iframe标签: ${iframeElements.length}个');
    for (final iframe in iframeElements) {
      final src = iframe.attributes['src'];
      if (src != null && src.isNotEmpty && !_shouldSkipUrl(src)) {
        print('[Kazumi Parser] 从iframe找到: $src');
        return src;
      }
    }

    // 4. 在script标签中查找视频URL（Kazumi的核心逻辑）
    final scriptElements = document.querySelectorAll('script');
    print('[Kazumi Parser] 发现script标签: ${scriptElements.length}个');
    
    for (final script in scriptElements) {
      final content = script.text;
      if (content.isEmpty) continue;

      // 查找直接的视频文件URL
      final directVideoPatterns = [
        RegExp(r'"(https?://[^"]*\.(?:mp4|m3u8|flv|avi|mkv|webm)[^"]*)"'),
        RegExp(r"'(https?://[^']*\.(?:mp4|m3u8|flv|avi|mkv|webm)[^']*)'"),
      ];

      for (final pattern in directVideoPatterns) {
        final matches = pattern.allMatches(content);
        for (final match in matches) {
          final url = match.group(1)!;
          if (!_shouldSkipUrl(url)) {
            print('[Kazumi Parser] 从script找到直接视频URL: $url');
            return url;
          }
        }
      }

      // 查找播放器配置中的URL（Kazumi的播放器解析逻辑）
      final configPatterns = [
        // 295yhw特殊处理 - 查找加密的播放器配置
        RegExp(r'player_aaaa\s*=\s*\{[^}]*["\x27]url["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        RegExp(r'var\s+player_aaaa\s*=\s*\{[^}]*["\x27]url["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        // 通用播放器配置
        RegExp(r'["\x27]url["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        RegExp(r'["\x27]src["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        RegExp(r'["\x27]file["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        // MacCMS播放器配置
        RegExp(r'MacPlayer\s*\.\s*Play\s*\([^)]*["\x27]([^"\x27]*)["\x27]'),
        // DPlayer配置
        RegExp(r'new\s+DPlayer\s*\([^)]*["\x27]url["\x27]\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        // 其他常见播放器
        RegExp(r'video\s*:\s*["\x27]([^"\x27]*)["\x27]'),
        RegExp(r'source\s*:\s*["\x27]([^"\x27]*)["\x27]'),
      ];

      for (final pattern in configPatterns) {
        final matches = pattern.allMatches(content);
        for (final match in matches) {
          final url = match.group(1)!;
          if (!_shouldSkipUrl(url) && url.length > 10) {
            print('[Kazumi Parser] 从script配置找到: $url');
            
            // 特殊处理295yhw等网站的加密URL
            if (pageUrl.contains('295yhw.com') && _isLikelyEncryptedUrl(url)) {
              print('[Kazumi Parser] 检测到295yhw加密URL，尝试解密');
              final decryptedUrl = _try295yhwDecrypt(url, pageUrl);
              if (decryptedUrl != null) {
                print('[Kazumi Parser] 295yhw解密成功: $decryptedUrl');
                return decryptedUrl;
              }
            }
            
            return url;
          }
        }
      }
    }

    print('[Kazumi Parser] 未在HTML中找到视频URL');
    return null;
  }

  /// Kazumi的视频源解码逻辑
  static String _decodeVideoSource(String iframeUrl) {
    print('[Kazumi Parser] 解码视频源: $iframeUrl');
    
    try {
      // 1. URL解码
      var decodedUrl = Uri.decodeFull(iframeUrl);
      
      // 2. 检查URL参数中的视频文件（Kazumi的核心逻辑）
      final uri = Uri.parse(decodedUrl);
      final params = uri.queryParameters;
      
      final videoRegExp = RegExp(r'(http[s]?://.*?\.m3u8)|(http[s]?://.*?\.mp4)', caseSensitive: false);
      
      // 遍历URL参数查找视频URL
      for (final entry in params.entries) {
        if (videoRegExp.hasMatch(entry.value)) {
          print('[Kazumi Parser] 从URL参数找到视频: ${entry.value}');
          return Uri.encodeFull(entry.value);
        }
      }
      
      // 3. Base64解码尝试
      if (_isLikelyBase64(iframeUrl)) {
        try {
          final decoded = _tryBase64Decode(iframeUrl);
          if (decoded != null && _isDirectVideoUrl(decoded)) {
            print('[Kazumi Parser] Base64解码成功: $decoded');
            return decoded;
          }
        } catch (e) {
          print('[Kazumi Parser] Base64解码失败: $e');
        }
      }
      
      print('[Kazumi Parser] 解码后返回原URL: $decodedUrl');
      return Uri.encodeFull(decodedUrl);
    } catch (e) {
      print('[Kazumi Parser] 解码失败: $e');
      return iframeUrl;
    }
  }

  /// 生成HTTP头信息 - 完全按照Kazumi的逻辑
  static Map<String, String> _generateHttpHeaders(String videoUrl, String pageUrl, KazumiRuleConfig config) {
    final headers = <String, String>{};
    
    // User-Agent
    headers['User-Agent'] = config.userAgent.isNotEmpty 
        ? config.userAgent 
        : _getRandomUserAgent();
    
    // Referer
    if (config.referer.isNotEmpty) {
      headers['Referer'] = config.referer;
    } else {
      headers['Referer'] = _getBaseUrl(pageUrl);
    }
    
    // 其他标准头
    headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8';
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    headers['Accept-Encoding'] = 'gzip, deflate';
    headers['Connection'] = 'keep-alive';
    
    return headers;
  }

  /// 检查是否为直接视频URL
  static bool _isDirectVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.m3u8', '.flv', '.avi', '.mkv', '.webm'];
    final lowerUrl = url.toLowerCase();
    return videoExtensions.any((ext) => lowerUrl.contains(ext));
  }

  /// 检查是否应该跳过的URL
  static bool _shouldSkipUrl(String url) {
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
    ];
    
    return skipPatterns.any((pattern) => url.contains(pattern));
  }

  /// 检查是否可能是Base64编码
  static bool _isLikelyBase64(String str) {
    if (str.length < 20) return false;
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=%_-]+$');
    return base64Pattern.hasMatch(str) && str.length >= 16;
  }

  /// 检查是否可能是加密URL
  static bool _isLikelyEncryptedUrl(String url) {
    // 检查是否包含域名但不是完整URL
    if (url.contains('.com') && !url.startsWith('http')) {
      return true;
    }
    
    // 检查是否是Base64编码
    if (_isLikelyBase64(url)) {
      return true;
    }
    
    // 检查是否包含特殊字符但不是URL
    if (url.length > 20 && !url.startsWith('http') && !url.contains('/')) {
      return true;
    }
    
    return false;
  }

  /// 尝试295yhw特殊解密
  static String? _try295yhwDecrypt(String encryptedUrl, String pageUrl) {
    try {
      print('[Kazumi Parser] 尝试295yhw解密: $encryptedUrl');
      
      // 方法1: 如果是域名，构造完整URL
      if (encryptedUrl.contains('295yhw.com') && !encryptedUrl.startsWith('http')) {
        final fullUrl = 'https://$encryptedUrl';
        print('[Kazumi Parser] 构造完整URL: $fullUrl');
        return fullUrl;
      }
      
      // 方法2: 尝试Base64解码
      if (_isLikelyBase64(encryptedUrl)) {
        final decoded = _tryBase64Decode(encryptedUrl);
        if (decoded != null && (decoded.startsWith('http') || decoded.contains('.m3u8') || decoded.contains('.mp4'))) {
          print('[Kazumi Parser] Base64解码成功: $decoded');
          return decoded;
        }
      }
      
      // 方法3: 尝试URL解码
      try {
        final urlDecoded = Uri.decodeComponent(encryptedUrl);
        if (urlDecoded != encryptedUrl && (urlDecoded.startsWith('http') || urlDecoded.contains('.m3u8'))) {
          print('[Kazumi Parser] URL解码成功: $urlDecoded');
          return urlDecoded;
        }
      } catch (e) {
        // URL解码失败，继续其他方法
      }
      
      // 方法4: 如果包含路径，尝试与页面URL组合
      if (encryptedUrl.contains('/') && !encryptedUrl.startsWith('http')) {
        final uri = Uri.parse(pageUrl);
        final combinedUrl = '${uri.scheme}://${uri.host}$encryptedUrl';
        print('[Kazumi Parser] 组合URL: $combinedUrl');
        return combinedUrl;
      }
      
      return null;
    } catch (e) {
      print('[Kazumi Parser] 295yhw解密失败: $e');
      return null;
    }
  }

  /// 尝试Base64解码
  static String? _tryBase64Decode(String encoded) {
    try {
      // 处理URL安全的Base64
      String base64Str = encoded.replaceAll('-', '+').replaceAll('_', '/');
      
      // 添加填充
      while (base64Str.length % 4 != 0) {
        base64Str += '=';
      }
      
      final bytes = base64Decode(base64Str);
      final decoded = utf8.decode(bytes);
      
      // 如果解码结果包含URL编码，再次解码
      if (decoded.contains('%')) {
        return Uri.decodeComponent(decoded);
      }
      
      return decoded;
    } catch (e) {
      return null;
    }
  }

  /// 解析相对URL为绝对URL
  static String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http')) {
      return url;
    }
    
    final uri = Uri.parse(baseUrl);
    
    if (url.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$url';
    } else {
      final basePath = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
      return '${uri.scheme}://${uri.host}$basePath$url';
    }
  }

  /// 获取基础URL
  static String _getBaseUrl(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}/';
  }

  /// 获取随机User-Agent（Kazumi的UA列表）
  static String _getRandomUserAgent() {
    final userAgents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/92.0.4515.107 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    ];
    return userAgents[DateTime.now().millisecond % userAgents.length];
  }
}

/// Kazumi风格的WebView解析器页面
class _KazumiWebViewParser extends StatefulWidget {
  final String episodeUrl;
  final KazumiRuleConfig config;

  const _KazumiWebViewParser({
    required this.episodeUrl,
    required this.config,
  });

  @override
  State<_KazumiWebViewParser> createState() => _KazumiWebViewParserState();
}

class _KazumiWebViewParserState extends State<_KazumiWebViewParser> {
  late WebViewController controller;
  String? foundVideoUrl;
  bool isLoading = true;
  Timer? timeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  void dispose() {
    timeoutTimer?.cancel();
    super.dispose();
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.config.userAgent.isNotEmpty 
          ? widget.config.userAgent 
          : KazumiVideoParser._getRandomUserAgent())
      ..addJavaScriptChannel(
        'JSBridgeDebug',
        onMessageReceived: (JavaScriptMessage message) {
          _handleVideoUrlFound(message.message, 'JSBridgeDebug');
        },
      )
      ..addJavaScriptChannel(
        'VideoBridgeDebug',
        onMessageReceived: (JavaScriptMessage message) {
          _handleVideoUrlFound(message.message, 'VideoBridgeDebug');
        },
      )
      ..addJavaScriptChannel(
        'IframeRedirectBridge',
        onMessageReceived: (JavaScriptMessage message) {
          print('[Kazumi WebView] Iframe重定向: ${message.message}');
          if (!widget.config.useNativePlayer) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.of(context).pop(null);
              }
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            print('[Kazumi WebView] 页面加载完成: $url');
            setState(() {
              isLoading = false;
            });
            
            await _injectKazumiScripts();
            
            // 设置超时
            timeoutTimer = Timer(const Duration(seconds: KazumiVideoParser._parseTimeout), () {
              if (foundVideoUrl == null && mounted) {
                print('[Kazumi WebView] 解析超时');
                Navigator.of(context).pop(null);
              }
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('[Kazumi WebView] 错误: ${error.description}');
            if (mounted) {
              Navigator.of(context).pop(null);
            }
          },
        ),
      );

    // 加载页面
    controller.loadRequest(Uri.parse(widget.episodeUrl));
  }

  void _handleVideoUrlFound(String message, String source) {
    print('[Kazumi WebView] $source 发现URL: $message');
    
    if (foundVideoUrl != null) return;
    
    // 过滤无效URL
    if (KazumiVideoParser._shouldSkipUrl(message)) {
      print('[Kazumi WebView] 跳过无效URL: $message');
      return;
    }
    
    // 检查是否为有效视频URL
    if (message.contains('http') || message.startsWith('//')) {
      setState(() {
        foundVideoUrl = message;
      });
      
      timeoutTimer?.cancel();
      Navigator.of(context).pop(message);
    }
  }

  Future<void> _injectKazumiScripts() async {
    try {
      if (widget.config.useNativePlayer && !widget.config.useLegacyParser) {
        // 注入Blob解析脚本（Kazumi的核心脚本）
        await controller.runJavaScript(_getBlobParserScript());
        print('[Kazumi WebView] Blob解析脚本注入成功');
      } else if (widget.config.useLegacyParser) {
        // 注入旧版iframe解析脚本
        await controller.runJavaScript(_getIframeParserScript());
        print('[Kazumi WebView] Iframe解析脚本注入成功');
      }
    } catch (e) {
      print('[Kazumi WebView] 脚本注入失败: $e');
    }
  }

  String _getBlobParserScript() {
    return '''
      (function() {
        console.log('[Kazumi] Blob解析脚本已加载: ' + window.location.href);
        
        // 拦截Response.text()方法来捕获M3U8内容
        const _r_text = window.Response.prototype.text;
        window.Response.prototype.text = function () {
          return new Promise((resolve, reject) => {
            _r_text.call(this).then((text) => {
              resolve(text);
              if (text.trim().startsWith("#EXTM3U")) {
                console.log('[Kazumi] 发现M3U8源: ' + this.url);
                VideoBridgeDebug.postMessage(this.url);
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
                console.log('[Kazumi] XHR发现M3U8源: ' + args[1]);
                VideoBridgeDebug.postMessage(args[1]);
              }
            } catch(e) {
              console.log('[Kazumi] XHR解析错误: ' + e);
            }
          });
          return _open.apply(this, args);
        }
        
        // iframe注入逻辑
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
                    console.log('[Kazumi] iframe发现M3U8源: ' + this.url);
                    VideoBridgeDebug.postMessage(this.url);
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
                    console.log('[Kazumi] iframe XHR发现M3U8源: ' + args[1]);
                    VideoBridgeDebug.postMessage(args[1]);
                  }
                } catch(e) {
                  console.log('[Kazumi] iframe XHR解析错误: ' + e);
                }
              });
              return iframe_open.apply(this, args);
            }
          } catch (e) {
            console.error('[Kazumi] iframe注入失败:', e);
          }
        }

        // 设置iframe监听器
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

        // 扫描video标签
        function scanVideoElements() {
          const videos = document.querySelectorAll('video');
          console.log('[Kazumi] 发现video标签数量: ' + videos.length);
          
          for (let video of videos) {
            let src = video.getAttribute('src');
            if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
              console.log('[Kazumi] 发现video源: ' + src);
              VideoBridgeDebug.postMessage(src);
              return;
            }
            
            const sources = video.getElementsByTagName('source');
            for (let source of sources) {
              src = source.getAttribute('src');
              if (src && src.trim() !== '' && !src.startsWith('blob:') && !src.includes('googleads')) {
                console.log('[Kazumi] 发现source源: ' + src);
                VideoBridgeDebug.postMessage(src);
                return;
              }
            }
          }
        }
        
        // 初始化
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', () => {
            setupIframeListeners();
            scanVideoElements();
          });
        } else {
          setupIframeListeners();
          scanVideoElements();
        }
        
        // 定时扫描
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
        
        console.log('[Kazumi] Blob解析脚本初始化完成');
      })();
    ''';
  }

  String _getIframeParserScript() {
    return '''
      (function() {
        console.log('[Kazumi] Iframe解析脚本已加载: ' + window.location.href);
        
        function processIframeElement(iframe) {
          console.log('[Kazumi] 处理iframe元素');
          let src = iframe.getAttribute('src');
          if (src) {
            console.log('[Kazumi] 发现iframe源: ' + src);
            JSBridgeDebug.postMessage(src);
          }
        }

        const observer = new MutationObserver((mutations) => {
          console.log('[Kazumi] 扫描iframe...');
          mutations.forEach(mutation => {
            if (mutation.type === 'attributes' && mutation.target.nodeName === 'IFRAME') {
              processIframeElement(mutation.target);
            } else {
              mutation.addedNodes.forEach(node => {
                if (node.nodeName === 'IFRAME') processIframeElement(node);
                if (node.querySelectorAll) {
                  node.querySelectorAll('iframe').forEach(processIframeElement);
                }
              });
            }
          });  
        });

        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src']
        });
        
        // 立即扫描现有iframe
        document.querySelectorAll('iframe').forEach(processIframeElement);
        
        console.log('[Kazumi] Iframe解析脚本初始化完成');
      })();
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频解析中'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // 隐藏返回按钮
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // 隐藏的WebView - 移到屏幕外运行
            Positioned(
              left: -2000,
              top: -2000,
              width: 1920,
              height: 1080,
              child: WebViewWidget(controller: controller),
            ),
            // 自定义加载界面
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
                  // 状态信息
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
                          isLoading ? '正在加载页面...' : '正在解析视频源...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
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