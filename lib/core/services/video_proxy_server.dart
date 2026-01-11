import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';

/// 本地代理服务器，用于为视频请求添加必要的HTTP头
class VideoProxyServer {
  static VideoProxyServer? _instance;
  static VideoProxyServer get instance => _instance ??= VideoProxyServer._();
  
  VideoProxyServer._();
  
  HttpServer? _server;
  int? _port;
  final Dio _dio = Dio();
  
  /// 存储URL到HTTP头的映射
  final Map<String, Map<String, String>> _urlHeaders = {};
  
  /// 启动代理服务器
  Future<int> start() async {
    if (_server != null) {
      return _port!;
    }
    
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    
    _server!.listen((HttpRequest request) async {
      await _handleRequest(request);
    });
    
    print('视频代理服务器启动在端口: $_port');
    return _port!;
  }
  
  /// 停止代理服务器
  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _port = null;
    _urlHeaders.clear();
  }
  
  /// 注册URL和对应的HTTP头
  String registerUrl(String originalUrl, Map<String, String> headers) {
    final proxyUrl = 'http://127.0.0.1:$_port/proxy?url=${Uri.encodeComponent(originalUrl)}';
    _urlHeaders[originalUrl] = headers;
    return proxyUrl;
  }
  
  /// 处理HTTP请求
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final uri = request.uri;
      
      if (uri.path == '/proxy' && uri.queryParameters.containsKey('url')) {
        await _handleProxyRequest(request);
      } else {
        // 返回404
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e) {
      print('代理服务器处理请求失败: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Internal Server Error');
        await request.response.close();
      } catch (_) {}
    }
  }
  
  /// 处理代理请求
  Future<void> _handleProxyRequest(HttpRequest request) async {
    final originalUrl = Uri.decodeComponent(request.uri.queryParameters['url']!);
    final headers = _urlHeaders[originalUrl] ?? {};
    
    try {
      // 构建请求头
      final requestHeaders = <String, String>{
        'User-Agent': headers['user-agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      };
      
      // 添加必要的防盗链头
      if (headers.containsKey('referer')) {
        requestHeaders['Referer'] = headers['referer']!;
      }
      
      // 根据域名添加特殊头信息
      final uri = Uri.parse(originalUrl);
      final domain = uri.host.toLowerCase();
      
      if (domain.contains('vbing.me')) {
        requestHeaders['Origin'] = headers['referer'] ?? 'https://www.libvio.cc';
        requestHeaders['Range'] = 'bytes=0-';
      } else if (domain.contains('moedot.net')) {
        requestHeaders['Range'] = 'bytes=0-';
        // moedot可能需要特殊的Cookie，这里可以根据需要添加
      }
      
      // 复制客户端的Range头（如果有）
      final clientRange = request.headers.value('range');
      if (clientRange != null) {
        requestHeaders['Range'] = clientRange;
      }
      
      print('代理请求: $originalUrl');
      print('请求头: $requestHeaders');
      
      // 发起请求
      final response = await _dio.get(
        originalUrl,
        options: Options(
          headers: requestHeaders,
          responseType: ResponseType.stream,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      
      // 设置响应头
      request.response.statusCode = response.statusCode!;
      
      // 复制重要的响应头
      final importantHeaders = [
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
        'cache-control',
        'etag',
        'last-modified',
      ];
      
      for (final headerName in importantHeaders) {
        final headerValue = response.headers.value(headerName);
        if (headerValue != null) {
          request.response.headers.set(headerName, headerValue);
        }
      }
      
      // 启用CORS
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      request.response.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type');
      
      // 流式传输响应数据
      await response.data.stream.pipe(request.response);
      
    } catch (e) {
      print('代理请求失败: $e');
      request.response.statusCode = HttpStatus.badGateway;
      request.response.write('Bad Gateway: $e');
      await request.response.close();
    }
  }
}