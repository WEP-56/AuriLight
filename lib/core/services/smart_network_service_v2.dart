import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';
import 'webview_environment_manager.dart';

/// 智能网络服务 V2 - 专门为 Windows 优化的 Dio + WebView 组合
/// 
/// 策略说明：
/// 1. 优先使用 Dio（快速、轻量）
/// 2. 失败时自动切换到 Windows WebView（处理 JS、Cloudflare、复杂反爬虫）
/// 3. WebView 获取内容后，Dio 复用信息下载图片
class SmartNetworkServiceV2 {
  static final SmartNetworkServiceV2 _instance = SmartNetworkServiceV2._internal();
  factory SmartNetworkServiceV2() => _instance;
  SmartNetworkServiceV2._internal();

  late Dio _dio;
  bool _dioInitialized = false;
  WebviewController? _webViewController;
  final Map<String, String> _cookieStore = {};
  bool _webViewInitialized = false;
  Future<void> _webViewLock = Future.value();

  void attachWebViewController(WebviewController controller) {
    _webViewController = controller;
    _webViewInitialized = true;
    debugPrint('🧩 已注入 UI WebViewController（后续 WebView 下载将复用此实例）');
  }

  Future<T> _withWebViewLock<T>(Future<T> Function() task) {
    final prev = _webViewLock;
    final completer = Completer<void>();
    _webViewLock = completer.future;

    return () async {
      await prev.catchError((_) {});
      try {
        return await task();
      } finally {
        completer.complete();
      }
    }();
  }

  /// 初始化网络服务
  void initialize() {
    if (_dioInitialized) return;
    _initializeDio();
    _dioInitialized = true;
  }

  void _initializeDio() {
    _dio = Dio();

    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 5,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language':
            'zh-CN,zh;q=0.8,zh-TW;q=0.7,zh-HK;q=0.5,en-US;q=0.3,en;q=0.2',
        'Cache-Control': 'no-cache',
        'Upgrade-Insecure-Requests': '1',
      },
    );

    // 显式控制 HttpClient（避免继承系统代理/PAC 导致端口异常）
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.connectionTimeout = const Duration(seconds: 30);
        client.idleTimeout = const Duration(seconds: 30);
        return client;
      },
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_cookieStore.isNotEmpty) {
            final cookieString = _cookieStore.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
            options.headers['Cookie'] = cookieString;
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          final setCookieHeaders = response.headers['set-cookie'];
          if (setCookieHeaders != null) {
            for (final cookie in setCookieHeaders) {
              _parseCookie(cookie);
            }
          }
          handler.next(response);
        },
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: true,
          logPrint: (obj) => debugPrint('🌐 Dio: $obj'),
        ),
      );
    }
  }

  void _parseCookie(String cookieString) {
    final parts = cookieString.split(';');
    if (parts.isNotEmpty) {
      final keyValue = parts[0].split('=');
      if (keyValue.length == 2) {
        _cookieStore[keyValue[0].trim()] = keyValue[1].trim();
      }
    }
  }

  String? _buildCdnFallbackUrl(String originalUrl, String fallback) {
    try {
      final origin = Uri.parse(originalUrl);

      final trimmed = fallback.trim();
      if (trimmed.isEmpty) return null;

      Uri? fallbackUri;
      if (trimmed.contains('://')) {
        fallbackUri = Uri.parse(trimmed);
      }

      final host = (fallbackUri?.host.isNotEmpty == true)
          ? fallbackUri!.host
          : trimmed
              .replaceAll(RegExp(r'^https?:\/\/'), '')
              .replaceAll(RegExp(r'^\/\/'), '');
      if (host.isEmpty) return null;

      final scheme = (fallbackUri?.scheme.isNotEmpty == true)
          ? fallbackUri!.scheme
          : origin.scheme;

      final port = (fallbackUri != null && fallbackUri.hasPort)
          ? fallbackUri.port
          : origin.hasPort
              ? origin.port
              : null;

      final replaced = origin.replace(
        scheme: scheme,
        host: host,
        port: port,
      );
      return replaced.toString();
    } catch (_) {
      return null;
    }
  }

  Future<NetworkResult<String>> getHtml(
    String url, {
    Map<String, String>? headers,
    bool forceWebView = false,
  }) async {
    initialize();
    // 非 Windows 平台没有 webview_windows，forceWebView 不能导致直接失败；仍需回退 Dio。
    final shouldTryDioFirst = !forceWebView || !Platform.isWindows;
    if (shouldTryDioFirst) {
      try {
        debugPrint('🚀 尝试使用 Dio 获取: $url');

        final response = await _dio.get(
          url,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            receiveDataWhenStatusError: true,
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final htmlContent = response.data.toString();
          debugPrint('✅ Dio 成功获取 HTML (${htmlContent.length} 字符)');
          return NetworkResult.success(htmlContent);
        }

        throw DioException(
          requestOptions: response.requestOptions,
          message: 'HTTP ${response.statusCode}',
        );
      } catch (e) {
        debugPrint('❌ Dio 失败: $e');
      }
    }

    if (Platform.isWindows) {
      try {
        debugPrint('🌐 切换到 Windows WebView 获取: $url');
        return await _getHtmlWithWindowsWebView(url, headers: headers);
      } catch (e) {
        debugPrint('❌ Windows WebView 也失败: $e');
        return NetworkResult.failure('所有网络策略都失败: $e');
      }
    }

    return NetworkResult.failure('非 Windows 平台，WebView 不可用');
  }

  Future<NetworkResult<String>> requestText(
    String url, {
    required String method,
    Map<String, String>? headers,
    dynamic data,
  }) async {
    initialize();
    try {
      final response = await _dio.request(
        url,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.plain,
          receiveDataWhenStatusError: true,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300 && response.data != null) {
        return NetworkResult.success(response.data.toString());
      }
      return NetworkResult.failure('HTTP $status');
    } catch (e) {
      return NetworkResult.failure('requestText失败: $e');
    }
  }

  Future<NetworkResult<String>> _getHtmlWithWindowsWebView(
    String url, {
    Map<String, String>? headers,
  }) async {
    return _withWebViewLock(() async {
      try {
        if (!_webViewInitialized) {
          await _initializeWindowsWebView();
        }

        if (_webViewController == null) {
          return NetworkResult.failure('Windows WebView 初始化失败');
        }

        // headers 目前未注入 WebView（需要更深层 API 支持）
        await _webViewController!.loadUrl(url);
        await _waitWebViewReady(timeout: const Duration(seconds: 12));

        // 某些页面（尤其是阅读页）会延迟插入图片节点；这里额外等待一会儿。
        final imgDeadline = DateTime.now().add(const Duration(seconds: 6));
        while (DateTime.now().isBefore(imgDeadline)) {
          try {
            final countRaw = await _webViewController!.executeScript(
              'document.querySelectorAll("img").length',
            );
            final count = int.tryParse((countRaw?.toString() ?? '').trim()) ?? 0;
            if (count > 0) break;
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 250));
        }

        // 直接取 outerHTML 在少数站点会出现 charset 乱码；改为 fetch + TextDecoder 强制 utf-8。
        final taskId = DateTime.now().microsecondsSinceEpoch.toString();

        final startJs = '''
          (function() {
            try {
              var id = "${taskId}";
              window.__kazu_html_dl = window.__kazu_html_dl || {};
              window.__kazu_html_dl[id] = { done: false, success: false };
              (async function() {
                try {
                  var u = window.location.href;
                  var resp = await fetch(u, { credentials: 'include' });
                  if (!resp || !resp.ok) {
                    window.__kazu_html_dl[id] = { done: true, success: false, error: 'HTTP ' + (resp ? resp.status : 'unknown') };
                    return;
                  }
                  var buf = await resp.arrayBuffer();
                  var text = new TextDecoder('utf-8').decode(buf);
                  window.__kazu_html_dl[id] = { done: true, success: true, text: text };
                } catch (e) {
                  window.__kazu_html_dl[id] = { done: true, success: false, error: (e && e.message) ? e.message : String(e) };
                }
              })();
              return JSON.stringify({ started: true, id: id });
            } catch (e) {
              return JSON.stringify({ started: false, error: (e && e.message) ? e.message : String(e) });
            }
          })();
        ''';

        final startRaw = await _webViewController!.executeScript(startJs);
        dynamic startParsed;
        final startString = startRaw?.toString() ?? '';
        if (startString.isNotEmpty) {
          try {
            startParsed = jsonDecode(startString);
          } catch (_) {
            try {
              startParsed = jsonDecode(jsonDecode(startString));
            } catch (_) {}
          }
        }

        if (startParsed is! Map || startParsed['started'] != true) {
          // fallback to outerHTML
          final html = await _webViewController!.executeScript(
            'document.documentElement.outerHTML',
          );
          final htmlString = html?.toString() ?? '';
          if (htmlString.isNotEmpty) {
            debugPrint('✅ Windows WebView 成功获取 HTML (${htmlString.length} 字符)');
            return NetworkResult.success(htmlString);
          }
          return NetworkResult.failure('Windows WebView 未返回 HTML 内容');
        }

        final pollJs = '''
          (function() {
            try {
              var id = "${taskId}";
              var o = window.__kazu_html_dl && window.__kazu_html_dl[id];
              return JSON.stringify(o || { done: false });
            } catch (e) {
              return JSON.stringify({ done: true, success: false, error: (e && e.message) ? e.message : String(e) });
            }
          })();
        ''';

        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(deadline)) {
          final raw = await _webViewController!.executeScript(pollJs);
          final rawString = raw?.toString() ?? '';
          if (rawString.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 150));
            continue;
          }

          dynamic parsed;
          try {
            parsed = jsonDecode(rawString);
          } catch (_) {
            try {
              parsed = jsonDecode(jsonDecode(rawString));
            } catch (_) {
              parsed = null;
            }
          }

          if (parsed is Map && parsed['done'] == true) {
            if (parsed['success'] == true && parsed['text'] is String) {
              final text = parsed['text'] as String;
              await _webViewController!.executeScript(
                'try { if (window.__kazu_html_dl) { delete window.__kazu_html_dl["${taskId}"]; } } catch (_) {}',
              );
              if (text.isNotEmpty) {
                debugPrint('✅ Windows WebView 成功获取 HTML (${text.length} 字符)');
                return NetworkResult.success(text);
              }
              return NetworkResult.failure('Windows WebView 未返回 HTML 内容');
            }

            final err = parsed['error']?.toString() ?? 'unknown';
            await _webViewController!.executeScript(
              'try { if (window.__kazu_html_dl) { delete window.__kazu_html_dl["${taskId}"]; } } catch (_) {}',
            );
            return NetworkResult.failure('Windows WebView 获取失败: $err');
          }

          await Future.delayed(const Duration(milliseconds: 150));
        }

        return NetworkResult.failure('Windows WebView 获取超时');
      } catch (e) {
        return NetworkResult.failure('Windows WebView 获取失败: $e');
      }
    });
  }

  Future<void> _initializeWindowsWebView() async {
    if (!Platform.isWindows) {
      throw Exception('WebView 仅在 Windows 平台可用');
    }

    if (_webViewController != null && _webViewInitialized) {
      debugPrint('🧩 检测到已注入的 UI WebViewController，跳过内部初始化');
      return;
    }

    debugPrint('🌐 开始初始化 Windows WebView...');

    final initialized = await WebViewEnvironmentManager.ensureInitialized();
    if (!initialized) {
      throw Exception('Windows WebView 环境初始化失败');
    }

    _webViewController = WebviewController();
    await _webViewController!.initialize();
    await _webViewController!.setPopupWindowPolicy(
      WebviewPopupWindowPolicy.deny,
    );

    _webViewInitialized = true;
    debugPrint('✅ Windows WebView 初始化成功');
  }

  Future<bool> _waitWebViewReady({Duration timeout = const Duration(seconds: 12)}) async {
    final controller = _webViewController;
    if (controller == null) return false;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final state = await controller.executeScript('document.readyState');
        final s = (state?.toString() ?? '').toLowerCase();
        if (s.contains('complete') || s.contains('interactive')) {
          return true;
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<NetworkResult<Uint8List>> downloadImage(
    String url, {
    Map<String, String>? headers,
    String? referer,
    List<String>? cdnFallbacks,
    bool forceWebView = false,
  }) async {
    initialize();
    debugPrint('📥 下载图片: $url');

    if (forceWebView && Platform.isWindows) {
      debugPrint('🌐 规则要求强制 WebView，跳过 Dio/CDN 探测');
      return await _downloadImageViaWebView(url, referer);
    }

    final dioResult = await _tryDioDownload(url, headers, referer);
    if (dioResult.isSuccess) {
      return dioResult;
    }

    debugPrint('❌ Dio 下载失败: ${dioResult.error}');

    final err = dioResult.error ?? '';
    final shouldTryFallback = err.contains('HandshakeException') ||
        err.contains('TlsException') ||
        err.contains('Connection terminated') ||
        err.contains('DioException [connection error]') ||
        err.contains('SocketException') ||
        err.toLowerCase().contains('timed out') ||
        err.contains('信号灯超时时间已到') ||
        err.contains('errno = 121');

    if (shouldTryFallback) {
      if (cdnFallbacks != null && cdnFallbacks.isNotEmpty) {
        debugPrint('🔄 检测到网络层问题，尝试 CDN 回退策略');

        for (int i = 0; i < cdnFallbacks.length; i++) {
          final fallbackUrl = _buildCdnFallbackUrl(url, cdnFallbacks[i]);
          if (fallbackUrl == null || fallbackUrl.isEmpty) {
            debugPrint('❌ CDN 回退 ${i + 1} 跳过：无效的 fallback=${cdnFallbacks[i]}');
            continue;
          }
          debugPrint('🔄 CDN 回退 ${i + 1}/${cdnFallbacks.length}: $fallbackUrl');

          final fallbackResult = await _tryDioDownload(fallbackUrl, headers, referer);
          if (fallbackResult.isSuccess) {
            debugPrint('✅ CDN 回退成功！');
            return fallbackResult;
          }
          debugPrint('❌ CDN 回退 ${i + 1} 失败: ${fallbackResult.error}');

          if (i < cdnFallbacks.length - 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        debugPrint('❌ 所有 CDN 回退都失败');
      }

      if (Platform.isWindows) {
        debugPrint('🌐 启动 WebView 渐进式下载');
        return await _downloadImageViaWebView(url, referer);
      }
    }

    return dioResult;
  }

  Future<NetworkResult<Uint8List>> _tryDioDownload(
    String url,
    Map<String, String>? headers,
    String? referer,
  ) async {
    try {
      final imageHeaders = {
        'Accept': 'image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Sec-Fetch-Dest': 'image',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Site': 'cross-site',
        if (referer != null) 'Referer': referer,
        ...?headers,
      };

      final response = await _dio.get(
        url,
        options: Options(
          headers: imageHeaders,
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final imageData = Uint8List.fromList(response.data);
        debugPrint(
          '✅ Dio 下载成功 (${(imageData.length / 1024).toStringAsFixed(1)}KB)',
        );
        return NetworkResult.success(imageData);
      }

      throw DioException(
        requestOptions: response.requestOptions,
        message: 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      return NetworkResult.failure('Dio 下载失败: $e');
    }
  }

  dom.Document parseHtml(String html) {
    return html_parser.parse(html);
  }

  Map<String, String> get cookies => Map.unmodifiable(_cookieStore);

  void clearCookies() {
    _cookieStore.clear();
    debugPrint('🧹 已清除所有 Cookie');
  }

  void addCookie(String name, String value) {
    _cookieStore[name] = value;
  }

  /// WebView 渐进式图片下载（终极解决方案）
  /// 当 Dio 遇到 SSL 握手问题时，使用 WebView 作为代理下载图片
  Future<NetworkResult<Uint8List>> _downloadImageViaWebView(
    String imageUrl,
    String? referer,
  ) async {
    return _withWebViewLock(() async {
      try {
        debugPrint('🌐 启动 WebView 渐进式图片下载: $imageUrl');

        if (!_webViewInitialized) {
          await _initializeWindowsWebView();
        }

        if (_webViewController == null) {
          return NetworkResult.failure('WebView 未初始化');
        }

        final controller = _webViewController!;

        // 步骤1: 访问 referer 页面建立会话
        if (referer != null && referer.isNotEmpty) {
          debugPrint('🌐 WebView 访问 referer: $referer');
          await controller.loadUrl(referer);
          await _waitWebViewReady(timeout: const Duration(seconds: 12));
        }

        // 步骤2: 打开图片 URL（使当前 origin = 图片域名，便于同源 XHR）
        debugPrint('🌐 WebView 打开图片页面');
        await controller.loadUrl(imageUrl);
        await _waitWebViewReady(timeout: const Duration(seconds: 12));

        final taskId = DateTime.now().microsecondsSinceEpoch.toString();

        // 注意：WebView2/Chromium 禁止“同步 XHR + responseType=arraybuffer”
        // 这里改为异步 fetch(arrayBuffer) 并把结果写入 window 全局变量，Dart 侧轮询获取。
        final referrer = (referer ?? '').replaceAll('\\', '\\\\').replaceAll('"', '\\"');

        final startJs = '''
          (function() {
            try {
              var id = "${taskId}";
              window.__kazu_image_dl = window.__kazu_image_dl || {};
              window.__kazu_image_dl[id] = { done: false, success: false };
              (async function() {
                try {
                  var url = window.location.href;
                  var init = { credentials: 'include' };
                  var forcedRef = "${referrer}";
                  if (forcedRef && forcedRef.length > 0) {
                    try {
                      init.referrer = forcedRef;
                      init.referrerPolicy = 'unsafe-url';
                    } catch (_) {}
                  }
                  var resp = await fetch(url, init);
                  if (!resp || !resp.ok) {
                    window.__kazu_image_dl[id] = { done: true, success: false, error: 'HTTP ' + (resp ? resp.status : 'unknown') };
                    return;
                  }
                  var buf = await resp.arrayBuffer();
                  var bytes = new Uint8Array(buf);
                  var chunkSize = 0x8000;
                  var binary = '';
                  for (var i = 0; i < bytes.length; i += chunkSize) {
                    var sub = bytes.subarray(i, i + chunkSize);
                    binary += String.fromCharCode.apply(null, sub);
                  }
                  var b64 = btoa(binary);
                  window.__kazu_image_dl[id] = { done: true, success: true, base64: b64, length: bytes.length };
                } catch (e) {
                  window.__kazu_image_dl[id] = { done: true, success: false, error: (e && e.message) ? e.message : String(e) };
                }
              })();
              return JSON.stringify({ started: true, id: id });
            } catch (e) {
              return JSON.stringify({ started: false, error: (e && e.message) ? e.message : String(e) });
            }
          })();
        ''';

        final startRaw = await controller.executeScript(startJs);
        debugPrint('🌐 WebView 下载启动(raw): $startRaw');

        dynamic startParsed;
        final startString = startRaw?.toString() ?? '';
        if (startString.isNotEmpty) {
          try {
            startParsed = jsonDecode(startString);
          } catch (_) {
            try {
              startParsed = jsonDecode(jsonDecode(startString));
            } catch (_) {}
          }
        }

        if (startParsed is! Map || startParsed['started'] != true) {
          final err = (startParsed is Map)
              ? (startParsed['error']?.toString() ?? 'unknown')
              : (startString.isEmpty ? 'empty' : startString);
          return NetworkResult.failure('WebView 启动下载失败: $err');
        }

        final pollJs = '''
          (function() {
            try {
              var id = "${taskId}";
              var o = window.__kazu_image_dl && window.__kazu_image_dl[id];
              return JSON.stringify(o || { done: false });
            } catch (e) {
              return JSON.stringify({ done: true, success: false, error: (e && e.message) ? e.message : String(e) });
            }
          })();
        ''';

        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(deadline)) {
          final raw = await controller.executeScript(pollJs);
          final rawString = raw?.toString() ?? '';
          if (rawString.isEmpty) {
            await Future.delayed(const Duration(milliseconds: 200));
            continue;
          }

          dynamic parsed;
          try {
            parsed = jsonDecode(rawString);
          } catch (_) {
            try {
              parsed = jsonDecode(jsonDecode(rawString));
            } catch (_) {
              parsed = null;
            }
          }

          if (parsed is Map && parsed['done'] == true) {
            if (parsed['success'] == true && parsed['base64'] is String) {
              final bytes = base64Decode(parsed['base64'] as String);
              debugPrint('✅ WebView 下载成功 (${bytes.length} bytes)');
              await controller.executeScript(
                'try { if (window.__kazu_image_dl) { delete window.__kazu_image_dl["${taskId}"]; } } catch (_) {}',
              );
              return NetworkResult.success(bytes);
            }
            final err = parsed['error']?.toString() ?? 'unknown';
            await controller.executeScript(
              'try { if (window.__kazu_image_dl) { delete window.__kazu_image_dl["${taskId}"]; } } catch (_) {}',
            );
            return NetworkResult.failure('WebView 下载失败: $err');
          }

          await Future.delayed(const Duration(milliseconds: 200));
        }

        return NetworkResult.failure('WebView 下载超时');
      } catch (e) {
        debugPrint('❌ WebView 渐进式下载异常: $e');
        return NetworkResult.failure('WebView 渐进式下载异常: $e');
      }
    });
  }

  /// 释放资源
  void dispose() {
    _dio.close();
    _webViewController = null;
    _webViewInitialized = false;
    _cookieStore.clear();
  }
}

/// 网络请求结果封装
class NetworkResult<T> {
  final bool isSuccess;
  final T? data;
  final String? error;

  NetworkResult._(this.isSuccess, this.data, this.error);

  factory NetworkResult.success(T data) {
    return NetworkResult._(true, data, null);
  }

  factory NetworkResult.failure(String error) {
    return NetworkResult._(false, null, error);
  }

  /// 是否成功
  bool get isFailure => !isSuccess;

  /// 获取数据，失败时抛出异常
  T get dataOrThrow {
    if (isSuccess && data != null) {
      return data!;
    }
    throw Exception(error ?? 'Unknown error');
  }

  /// 获取数据，失败时返回默认值
  T getDataOrDefault(T defaultValue) {
    return isSuccess && data != null ? data! : defaultValue;
  }
}