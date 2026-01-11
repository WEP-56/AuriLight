import 'dart:typed_data';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../utils/logger.dart';

/// 漫画网络服务 - 为每个规则源提供独立的网络实例
/// 确保不同源的网络配置（UA、Cookie、Referer等）完全隔离
class MangaNetworkService {
  static final MangaNetworkService _instance = MangaNetworkService._internal();
  factory MangaNetworkService() => _instance;
  MangaNetworkService._internal();

  /// 每个规则源的独立网络实例
  final Map<String, MangaSourceNetworkInstance> _sourceInstances = {};

  /// 获取指定规则源的网络实例
  MangaSourceNetworkInstance getSourceInstance(String sourceKey) {
    return _sourceInstances.putIfAbsent(sourceKey, () {
      Logger.info('创建漫画源网络实例: $sourceKey');
      return MangaSourceNetworkInstance(sourceKey);
    });
  }

  /// 发送HTTP请求
  Future<MangaNetworkResponse> request({
    required String sourceKey,
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic data,
    bool bytes = false,
  }) async {
    final instance = getSourceInstance(sourceKey);
    return await instance.request(
      method: method,
      url: url,
      headers: headers,
      data: data,
      bytes: bytes,
    );
  }

  /// GET请求
  Future<MangaNetworkResponse> get(String sourceKey, String url, {Map<String, String>? headers}) {
    return request(sourceKey: sourceKey, method: 'GET', url: url, headers: headers);
  }

  /// POST请求
  Future<MangaNetworkResponse> post(String sourceKey, String url, {Map<String, String>? headers, dynamic data}) {
    return request(sourceKey: sourceKey, method: 'POST', url: url, headers: headers, data: data);
  }

  /// 获取图片数据（专用于漫画图片加载）
  Future<Uint8List?> getImageBytes({
    required String sourceKey,
    required String imageUrl,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await request(
        sourceKey: sourceKey,
        method: 'GET',
        url: imageUrl,
        headers: headers,
        bytes: true,
      );
      
      if (response.isSuccess && response.bodyBytes != null) {
        return response.bodyBytes;
      }
      
      Logger.warning('图片加载失败: $imageUrl, 状态码: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('图片加载异常: $imageUrl, 错误: $e');
      return null;
    }
  }

  /// 设置源的Cookie
  void setCookies(String sourceKey, String url, List<Cookie> cookies) {
    final instance = getSourceInstance(sourceKey);
    instance.setCookies(url, cookies);
  }

  /// 获取源的Cookie
  Future<List<Cookie>> getCookies(String sourceKey, String url) async {
    final instance = getSourceInstance(sourceKey);
    return await instance.getCookies(url);
  }

  /// 清除源的Cookie
  void clearCookies(String sourceKey, String url) {
    final instance = getSourceInstance(sourceKey);
    instance.clearCookies(url);
  }

  /// 清理指定源的网络实例
  void clearSource(String sourceKey) {
    final instance = _sourceInstances.remove(sourceKey);
    instance?.dispose();
    Logger.info('清理漫画源网络实例: $sourceKey');
  }

  /// 清理所有网络实例
  void clearAll() {
    for (final instance in _sourceInstances.values) {
      instance.dispose();
    }
    _sourceInstances.clear();
    Logger.info('清理所有漫画源网络实例');
  }
}

/// 单个规则源的网络实例
class MangaSourceNetworkInstance {
  final String sourceKey;
  late final Dio _dio;
  late final CookieJar _cookieJar;

  MangaSourceNetworkInstance(this.sourceKey) {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30), // 增加连接超时
      receiveTimeout: const Duration(seconds: 60),  // 增加接收超时
      sendTimeout: const Duration(seconds: 30),     // 增加发送超时
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ));

    // 添加Cookie管理
    _dio.interceptors.add(CookieManager(_cookieJar));
    
    // 添加日志拦截器
    _dio.interceptors.add(_MangaLogInterceptor(sourceKey));
    
    // 添加证书验证绕过和DNS配置（用于测试）
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true; // 忽略证书错误
      
      // 尝试配置DNS解析
      try {
        // 设置连接超时
        client.connectionTimeout = const Duration(seconds: 30);
        client.idleTimeout = const Duration(seconds: 30);
      } catch (e) {
        Logger.warning('[$sourceKey] DNS配置失败: $e');
      }
      
      return client;
    };
  }

  /// 发送请求
  Future<MangaNetworkResponse> request({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic data,
    bool bytes = false,
  }) async {
    try {
      Logger.info('[$sourceKey] 开始请求: $method $url');
      Logger.debug('[$sourceKey] 请求头: $headers');
      
      // 设置更真实的User-Agent和请求头
      final requestHeaders = <String, String>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
        ...?headers,
      };

      Logger.debug('[$sourceKey] 最终请求头: $requestHeaders');

      final response = await _dio.request(
        url,
        data: data,
        options: Options(
          method: method,
          headers: requestHeaders,
          responseType: bytes ? ResponseType.bytes : ResponseType.plain,
        ),
      );

      Logger.info('[$sourceKey] 响应状态码: ${response.statusCode}');
      Logger.debug('[$sourceKey] 响应头: ${response.headers.map}');

      return MangaNetworkResponse(
        statusCode: response.statusCode ?? 0,
        headers: response.headers.map,
        body: bytes ? null : response.data?.toString(),
        bodyBytes: bytes ? response.data as Uint8List? : null,
        isSuccess: (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300,
      );
    } catch (e) {
      Logger.error('[$sourceKey] 请求异常: $e');
      
      // 提供更详细的错误信息
      String errorDetail = '';
      if (e is DioException) {
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            errorDetail = '连接超时';
            break;
          case DioExceptionType.sendTimeout:
            errorDetail = '发送超时';
            break;
          case DioExceptionType.receiveTimeout:
            errorDetail = '接收超时';
            break;
          case DioExceptionType.badCertificate:
            errorDetail = '证书错误';
            break;
          case DioExceptionType.connectionError:
            errorDetail = '连接错误';
            break;
          case DioExceptionType.unknown:
            errorDetail = '未知网络错误: ${e.message}';
            break;
          default:
            errorDetail = 'Dio错误: ${e.message}';
        }
      } else {
        errorDetail = e.toString();
      }
      
      Logger.error('网络请求失败 [$sourceKey]: $method $url, 详细错误: $errorDetail');
      
      return MangaNetworkResponse(
        statusCode: 0,
        headers: {},
        body: null,
        bodyBytes: null,
        isSuccess: false,
        error: errorDetail,
      );
    }
  }

  /// 设置Cookie
  void setCookies(String url, List<Cookie> cookies) {
    _cookieJar.saveFromResponse(Uri.parse(url), cookies);
  }

  /// 获取Cookie
  Future<List<Cookie>> getCookies(String url) async {
    return await _cookieJar.loadForRequest(Uri.parse(url));
  }

  /// 清除Cookie
  void clearCookies(String url) {
    _cookieJar.delete(Uri.parse(url));
  }

  /// 释放资源
  void dispose() {
    _dio.close();
  }
}

/// 漫画网络响应
class MangaNetworkResponse {
  final int statusCode;
  final Map<String, List<String>> headers;
  final String? body;
  final Uint8List? bodyBytes;
  final bool isSuccess;
  final String? error;

  MangaNetworkResponse({
    required this.statusCode,
    required this.headers,
    this.body,
    this.bodyBytes,
    required this.isSuccess,
    this.error,
  });

  /// 获取响应头
  String? getHeader(String name) {
    final values = headers[name.toLowerCase()];
    return values?.isNotEmpty == true ? values!.first : null;
  }

  @override
  String toString() {
    return 'MangaNetworkResponse(status: $statusCode, success: $isSuccess)';
  }
}

/// 漫画网络日志拦截器
class _MangaLogInterceptor extends Interceptor {
  final String sourceKey;

  _MangaLogInterceptor(this.sourceKey);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Logger.info('[$sourceKey] ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final size = response.data is Uint8List 
        ? (response.data as Uint8List).length 
        : response.data?.toString().length ?? 0;
    Logger.info('[$sourceKey] ${response.statusCode} ${response.realUri} ($size bytes)');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Logger.error('[$sourceKey] ${err.requestOptions.method} ${err.requestOptions.uri} - ${err.message}');
    handler.next(err);
  }
}