import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/parser.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../models/unified_rule.dart';
import '../models/anime_item.dart';
import '../utils/logger.dart';

/// 重试拦截器 - 基于 Kazumi 的错误处理策略
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;
  final void Function(String) logPrint;

  RetryInterceptor({
    required this.dio,
    this.retries = 3,
    this.retryDelays = const [
      Duration(milliseconds: 1000),
      Duration(milliseconds: 2000),
      Duration(milliseconds: 3000),
    ],
    required this.logPrint,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final retryCount = extra['retryCount'] ?? 0;

    if (retryCount < retries && _shouldRetry(err)) {
      logPrint('Retrying request (${retryCount + 1}/$retries): ${err.requestOptions.uri}');
      
      // 等待重试延迟
      if (retryCount < retryDelays.length) {
        await Future.delayed(retryDelays[retryCount]);
      } else {
        await Future.delayed(retryDelays.last);
      }

      // 更新重试计数
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      
      // 随机化 User-Agent
      err.requestOptions.headers['User-Agent'] = _getRandomUA();

      try {
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        // 继续到下一次重试或失败
      }
    }

    // 提供更友好的错误信息
    final friendlyError = _getFriendlyError(err);
    final newError = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: friendlyError,
      message: friendlyError,
    );
    
    super.onError(newError, handler);
  }

  /// 判断是否应该重试
  bool _shouldRetry(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        // 对于某些状态码进行重试
        final statusCode = err.response?.statusCode;
        return statusCode == 403 || statusCode == 429 || statusCode == 502 || statusCode == 503 || statusCode == 504;
      default:
        return false;
    }
  }

  /// 获取友好的错误信息
  String _getFriendlyError(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时，请检查网络连接或尝试更换网络环境';
      case DioExceptionType.receiveTimeout:
        return '接收数据超时，服务器响应缓慢';
      case DioExceptionType.sendTimeout:
        return '发送请求超时，请检查网络连接';
      case DioExceptionType.connectionError:
        final errorMsg = err.error.toString().toLowerCase();
        if (errorMsg.contains('failed host lookup')) {
          return 'DNS解析失败，请检查网络连接或尝试更换DNS服务器';
        } else if (errorMsg.contains('connection refused')) {
          return '连接被拒绝，目标服务器可能不可用';
        } else if (errorMsg.contains('connection terminated during handshake') || 
                   errorMsg.contains('handshakeexception')) {
          return 'SSL握手失败，网络不稳定或服务器证书问题，正在重试...';
        } else if (errorMsg.contains('network is unreachable')) {
          return '网络不可达，请检查网络连接';
        } else if (errorMsg.contains('software caused connection abort')) {
          return '连接被中断，可能是网络不稳定';
        }
        return '网络连接错误，请检查网络设置';
      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode;
        switch (statusCode) {
          case 403:
            return '访问被拒绝(403)，可能触发了反爬虫机制，正在重试...';
          case 404:
            return '页面不存在(404)，请检查规则配置';
          case 429:
            return '请求过于频繁(429)，正在重试...';
          case 500:
            return '服务器内部错误(500)';
          case 502:
            return '网关错误(502)，服务器暂时不可用';
          case 503:
            return '服务不可用(503)，服务器维护中';
          case 504:
            return '网关超时(504)，服务器响应超时';
          default:
            return '服务器响应错误($statusCode)';
        }
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return 'SSL证书验证失败，正在重试...';
      case DioExceptionType.unknown:
        final errorMsg = err.error.toString().toLowerCase();
        if (errorMsg.contains('handshakeexception')) {
          return 'SSL握手失败，网络不稳定，正在重试...';
        }
        return '未知网络错误，请检查网络连接';
    }
  }

  /// 获取随机 User-Agent
  String _getRandomUA() {
    const userAgents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1',
    ];
    final random = Random();
    return userAgents[random.nextInt(userAgents.length)];
  }
}

/// 基于 Kazumi 实现的网络服务
class KazumiNetworkService {
  static final KazumiNetworkService _instance = KazumiNetworkService._internal();
  factory KazumiNetworkService() => _instance;
  KazumiNetworkService._internal();

  late final Dio _dio;

  /// Kazumi 的 User-Agent 列表
  static const List<String> _userAgentsList = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0',
  ];

  /// Kazumi 的 Accept-Language 列表
  static const List<String> _acceptLanguageList = [
    'zh-CN,zh;q=0.9',
    'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    'zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6',
  ];

  /// 初始化网络服务
  void initialize() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 12000), // 使用Kazumi的超时设置
      receiveTimeout: const Duration(milliseconds: 12000), // 使用Kazumi的超时设置
      sendTimeout: const Duration(milliseconds: 10000),
      headers: {
        // 简化请求头，只保留必要的
        'User-Agent': _getRandomUA(),
      },
    ));

    // 设置 HTTP 客户端适配器 - 简化配置，按照Kazumi的方式
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient client = HttpClient();
        
        // 忽略SSL证书验证
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        
        return client;
      },
    );

    // 添加重试拦截器 - 简化配置
    _dio.interceptors.add(RetryInterceptor(
      dio: _dio,
      logPrint: (message) => Logger.info(message),
      retries: 3, // 使用Kazumi的重试次数
      retryDelays: const [
        Duration(milliseconds: 1000),
        Duration(milliseconds: 2000),
        Duration(milliseconds: 3000),
      ],
    ));

    // 添加日志拦截器 - 按照Kazumi的方式
    _dio.interceptors.add(LogInterceptor(
      request: false,
      requestHeader: false,
      responseHeader: false,
    ));

    // 设置BackgroundTransformer - 按照Kazumi的方式
    _dio.transformer = BackgroundTransformer();
    
    // 设置状态码验证 - 按照Kazumi的方式
    _dio.options.validateStatus = (int? status) {
      return status != null && status >= 200 && status < 300;
    };

    _dio.options.validateStatus = (int? status) {
      return status! >= 200 && status < 400; // 允许重定向状态码
    };
  }

  /// 测试搜索请求 - 用于调试XPath选择器
  Future<String> testSearchRequest(UnifiedRule rule, String keyword) async {
    try {
      Logger.info('测试搜索请求 - 规则: ${rule.name}, 关键词: $keyword');
      
      final searchConfig = rule.searchConfig;
      if (searchConfig == null) {
        throw Exception('规则 ${rule.name} 缺少搜索配置');
      }

      String queryURL = searchConfig.searchUrl.replaceAll('@keyword', Uri.encodeComponent(keyword));
      Logger.info('请求URL: $queryURL');

      dynamic resp;
      if (searchConfig.usePost) {
        Uri uri = Uri.parse(queryURL);
        Map<String, String> queryParams = uri.queryParameters;
        Uri postUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
        );
        
        var httpHeaders = {
          'referer': _getRuleSpecificReferer(rule),
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept-Language': _getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
          'User-Agent': _getRuleSpecificUA(rule),
        };
        
        resp = await _dio.post(
          postUri.toString(),
          options: Options(headers: httpHeaders),
          data: queryParams,
        );
      } else {
        var httpHeaders = {
          'referer': '${rule.baseUrl}/',
          'Accept-Language': _getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
        };
        
        resp = await _dio.get(
          queryURL,
          options: Options(headers: httpHeaders),
        );
      }

      // 直接使用响应数据，Dio已经自动处理了gzip解压缩和编码
      String htmlString = resp.data.toString();

      return htmlString;
    } catch (e) {
      Logger.error('测试搜索请求失败: $e');
      rethrow;
    }
  }

  /// 测试XPath选择器 - 用于调试
  Map<String, dynamic> testXPathSelectors(String htmlString, UnifiedRule rule) {
    try {
      final searchConfig = rule.searchConfig;
      if (searchConfig == null) {
        return {'error': '规则缺少搜索配置'};
      }

      var htmlElement = parse(htmlString).documentElement!;
      
      final result = <String, dynamic>{};
      
      // 测试搜索列表选择器
      final searchListSelector = searchConfig.searchList ?? '';
      try {
        final searchListNodes = htmlElement.queryXPath(searchListSelector).nodes;
        result['searchList'] = {
          'selector': searchListSelector,
          'count': searchListNodes.length,
          'success': true,
        };
        
        if (searchListNodes.isNotEmpty) {
          // 测试第一个节点的子选择器
          final firstNode = searchListNodes.first;
          
          // 测试名称选择器
          final nameSelector = searchConfig.searchName ?? '';
          try {
            final nameNode = firstNode.queryXPath(nameSelector).node;
            final nameText = nameNode?.text?.trim() ?? '';
            result['searchName'] = {
              'selector': nameSelector,
              'text': nameText,
              'success': nameText.isNotEmpty,
            };
          } catch (e) {
            result['searchName'] = {
              'selector': nameSelector,
              'error': e.toString(),
              'success': false,
            };
          }
          
          // 测试链接选择器
          final resultSelector = searchConfig.searchResult ?? '';
          try {
            final srcNode = firstNode.queryXPath(resultSelector).node;
            final srcHref = srcNode?.attributes['href'] ?? '';
            result['searchResult'] = {
              'selector': resultSelector,
              'href': srcHref,
              'success': srcHref.isNotEmpty,
            };
          } catch (e) {
            result['searchResult'] = {
              'selector': resultSelector,
              'error': e.toString(),
              'success': false,
            };
          }
        }
      } catch (e) {
        result['searchList'] = {
          'selector': searchListSelector,
          'error': e.toString(),
          'success': false,
        };
      }
      
      return result;
    } catch (e) {
      return {'error': '测试XPath选择器失败: $e'};
    }
  }
  String _getRandomUA() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return _userAgentsList[random % _userAgentsList.length];
  }

  /// 获取规则特定的User-Agent
  String _getRuleSpecificUA(UnifiedRule rule) {
    // 如果规则指定了userAgent，使用它；否则使用随机UA
    if (rule.userAgent != null && rule.userAgent!.isNotEmpty) {
      return rule.userAgent!;
    }
    return _getRandomUA();
  }

  /// 获取规则特定的Referer
  String _getRuleSpecificReferer(UnifiedRule rule) {
    // 如果规则指定了referer，使用它；否则使用baseUrl
    if (rule.referer != null && rule.referer!.isNotEmpty) {
      return rule.referer!;
    }
    return '${rule.baseUrl}/';
  }

  /// 获取随机 Accept-Language（基于 Kazumi 的实现）
  String _getRandomAcceptedLanguage() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return _acceptLanguageList[random % _acceptLanguageList.length];
  }

  /// 搜索动漫 - 完全基于 Kazumi 的 queryBangumi 实现，增强错误处理
  Future<List<AnimeItem>> searchAnime(UnifiedRule rule, String keyword) async {
    try {
      Logger.info('开始搜索 - 规则: ${rule.name}, 关键词: $keyword');
      
      if (rule.searchConfig == null) {
        throw Exception('规则 ${rule.name} 没有搜索配置');
      }

      final searchConfig = rule.searchConfig!;
      String queryURL = searchConfig.searchUrl.replaceAll('@keyword', keyword);
      Logger.info('搜索URL: $queryURL');
      
      // 检查规则是否被标记为废弃
      if (rule.rawData['deprecated'] == true) {
        Logger.warning('规则 ${rule.name} 已被标记为废弃，可能不可用');
      }
      
      dynamic resp;
      List<AnimeItem> searchItems = [];

      // 添加随机延迟以避免反爬虫 - 减少延迟时间
      final delay = Random().nextInt(300) + 100; // 100-400ms，更短的延迟
      Logger.info('等待 ${delay}ms 以避免反爬虫...');
      await Future.delayed(Duration(milliseconds: delay));

      if (searchConfig.usePost) {
        Logger.info('使用 POST 请求搜索...');
        // POST 请求处理 - 完全按照 Kazumi 的方式
        Uri uri = Uri.parse(queryURL);
        Map<String, String> queryParams = uri.queryParameters;
        Uri postUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
        );
        
        // 使用规则特定的配置，简化请求头 - 完全按照Kazumi的方式
        var httpHeaders = {
          'referer': '${rule.baseUrl}/',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept-Language': _getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
        };
        
        resp = await _dio.post(
          postUri.toString(),
          options: Options(headers: httpHeaders),
          data: queryParams,
        );
      } else {
        Logger.info('使用 GET 请求搜索...');
        // GET 请求处理 - 完全按照Kazumi的方式，简化请求头
        var httpHeaders = {
          'referer': '${rule.baseUrl}/',
          'Accept-Language': _getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
        };
        
        resp = await _dio.get(
          queryURL,
          options: Options(headers: httpHeaders),
        );
      }

      Logger.info('收到响应，状态码: ${resp.statusCode}');

      // 直接使用响应数据，Dio已经自动处理了gzip解压缩和编码
      String htmlString = resp.data.toString();
      Logger.info('响应内容长度: ${htmlString.length} 字符');
      
      // 检查是否被反爬虫拦截或遇到验证码 - 扩展检查
      if (htmlString.length < 100) {
        Logger.warning('响应内容过短，可能被拦截');
        throw Exception('响应内容异常，可能触发了反爬虫机制');
      }
      
      // 检查常见的验证码和拦截页面 - 更宽松的检测
      final lowerHtml = htmlString.toLowerCase();
      
      // 只检测非常明确的Cloudflare验证码页面
      final strictCaptchaPatterns = [
        // Cloudflare验证码的明确特征
        lowerHtml.contains('just a moment') && lowerHtml.contains('cloudflare') && lowerHtml.contains('ray id'),
        lowerHtml.contains('cf-browser-verification') && lowerHtml.contains('challenge'),
        lowerHtml.contains('checking your browser') && lowerHtml.contains('cloudflare'),
        // 其他明确的验证码页面
        lowerHtml.contains('captcha') && lowerHtml.contains('solve') && lowerHtml.contains('verify'),
      ];
      
      // 只有当检测到非常明确的验证码特征时才报错
      if (strictCaptchaPatterns.any((pattern) => pattern)) {
        Logger.warning('检测到明确的验证码页面');
        throw Exception('该网站需要验证码验证，暂时无法搜索');
      }
      
      // 对于可能的验证码页面，只记录警告但不阻止搜索
      if (lowerHtml.contains('验证码') || lowerHtml.contains('captcha')) {
        Logger.warning('页面可能包含验证码，但继续尝试解析');
      }
      
      var htmlElement = parse(htmlString).documentElement!;
      Logger.info('HTML 解析完成');
      
      // 使用 XPath 解析搜索结果 - 完全按照 Kazumi 的方式
      final searchListSelector = searchConfig.searchList ?? '';
      Logger.info('使用搜索列表选择器: $searchListSelector');
      
      if (searchListSelector.isEmpty) {
        Logger.warning('搜索列表选择器为空');
        throw Exception('规则配置错误：搜索列表选择器为空');
      }
      
      final searchListNodes = htmlElement.queryXPath(searchListSelector).nodes;
      Logger.info('找到 ${searchListNodes.length} 个搜索结果节点');
      
      if (searchListNodes.isEmpty) {
        Logger.warning('没有找到搜索结果，可能是选择器不匹配或页面结构变化');
        
        // 详细的调试信息
        Logger.info('调试信息:');
        Logger.info('- 搜索URL: $queryURL');
        Logger.info('- 搜索列表选择器: $searchListSelector');
        Logger.info('- 页面标题: ${htmlElement.querySelector('title')?.text ?? '未找到标题'}');
        
        // 尝试一些常见的选择器来帮助调试
        final commonSelectors = [
          '//div',
          '//a',
          '//li',
          '//ul',
          '//section',
          '//article',
        ];
        
        for (final selector in commonSelectors) {
          try {
            final nodes = htmlElement.queryXPath(selector).nodes;
            Logger.info('- 选择器 "$selector" 找到 ${nodes.length} 个节点');
          } catch (e) {
            Logger.warning('- 选择器 "$selector" 失败: $e');
          }
        }
        
        // 记录页面内容的一部分用于调试
        final preview = htmlString.length > 2000 ? htmlString.substring(0, 2000) : htmlString;
        Logger.info('页面内容预览: $preview...');
        
        // 返回空结果而不是抛出异常 - 这样UI可以显示"无结果"
        return searchItems;
      }
      
      int processedCount = 0;
      // 完全按照 Kazumi 的方式处理 - 使用空的 catch 块
      searchListNodes.forEach((element) {
        try {
          final nameSelector = searchConfig.searchName ?? '';
          final resultSelector = searchConfig.searchResult ?? '';
          
          // 增加调试信息
          Logger.info('处理节点，使用选择器 - 名称: "$nameSelector", 链接: "$resultSelector"');
          
          String name = '';
          String src = '';
          
          // 更健壮的XPath查询
          try {
            final nameNode = element.queryXPath(nameSelector).node;
            name = nameNode?.text?.trim() ?? '';
            Logger.info('提取到名称: "$name"');
          } catch (e) {
            Logger.warning('名称选择器失败: $e');
          }
          
          try {
            final srcNode = element.queryXPath(resultSelector).node;
            src = srcNode?.attributes['href'] ?? '';
            Logger.info('提取到链接: "$src"');
          } catch (e) {
            Logger.warning('链接选择器失败: $e');
          }
          
          if (name.isNotEmpty && src.isNotEmpty) {
            // 构建完整URL - 按照 Kazumi 的方式
            String fullUrl = src;
            if (!src.startsWith('http')) {
              if (src.startsWith('/')) {
                fullUrl = '${rule.baseUrl}$src';
              } else {
                fullUrl = '${rule.baseUrl}/$src';
              }
            }
            
            AnimeItem searchItem = AnimeItem(
              title: name,
              detailUrl: fullUrl,
              coverUrl: null, // 暂时不处理封面
              ruleName: rule.name,
              ruleKey: rule.key,
            );
            searchItems.add(searchItem);
            processedCount++;
            
            Logger.info('Plugin: ${rule.name} $name $fullUrl');
          } else {
            Logger.warning('跳过无效项目 - 名称: "$name", 链接: "$src"');
          }
        } catch (e) {
          // Kazumi 使用空的 catch 块，但我们记录一下调试信息
          Logger.warning('处理搜索项目时出错: $e');
        }
      });
      
      Logger.info('搜索完成，成功解析 ${searchItems.length} 个结果');
      
      // 如果解析了节点但没有有效结果，可能是选择器问题
      if (searchListNodes.isNotEmpty && searchItems.isEmpty) {
        Logger.warning('找到了搜索节点但无法解析出有效结果，可能是选择器配置问题');
      }
      
      return searchItems;
    } on DioException catch (e) {
      // 网络错误已经由拦截器处理，这里只需要重新抛出
      Logger.error('网络错误 - 规则: ${rule.name}, 错误: ${e.message}');
      rethrow;
    } catch (e) {
      Logger.error('搜索失败 - 规则: ${rule.name}, 错误: $e');
      rethrow;
    }
  }

  /// 获取章节列表 - 完全基于 Kazumi 的 querychapterRoads 实现
  Future<List<AnimeEpisode>> getEpisodes(UnifiedRule rule, String url) async {
    try {
      Logger.info('获取章节列表: $url');
      
      List<AnimeEpisode> episodeList = [];
      
      // 预处理 - 按照 Kazumi 的方式
      String queryURL = url;
      if (!url.contains('https')) {
        queryURL = url.replaceAll('http', 'https');
      }
      if (url.contains(rule.baseUrl)) {
        queryURL = url;
      } else {
        queryURL = rule.baseUrl + url;
      }
      
      // 使用规则特定的配置
      var httpHeaders = {
        'referer': _getRuleSpecificReferer(rule),
        'Accept-Language': _getRandomAcceptedLanguage(),
        'Connection': 'keep-alive',
        'User-Agent': _getRuleSpecificUA(rule),
      };
      
      var resp = await _dio.get(queryURL, options: Options(
        headers: httpHeaders,
        responseType: ResponseType.plain, // 改回plain，让Dio自动处理解压缩
      ));
      
      // 直接使用响应数据，Dio已经自动处理了gzip解压缩和编码
      String htmlString = resp.data.toString();
      var htmlElement = parse(htmlString).documentElement!;
      
      int count = 1;
      
      // 使用 XPath 解析章节路线 - 完全按照 Kazumi 的方式
      if (rule.detailConfig?.chaptersSelector != null && rule.playConfig?.playUrlSelector != null) {
        // 完全按照 Kazumi 的方式处理 - 使用空的 catch 块
        htmlElement.queryXPath(rule.detailConfig!.chaptersSelector!).nodes.forEach((element) {
          try {
            List<String> chapterUrlList = [];
            List<String> chapterNameList = [];
            
            element.queryXPath(rule.playConfig!.playUrlSelector!).nodes.forEach((item) {
              String itemUrl = item.node.attributes['href'] ?? '';
              String itemName = item.node.text ?? '';
              chapterUrlList.add(itemUrl);
              chapterNameList.add(itemName.replaceAll(RegExp(r'\s+'), ''));
            });
            
            if (chapterUrlList.isNotEmpty && chapterNameList.isNotEmpty) {
              for (int i = 0; i < chapterUrlList.length; i++) {
                String episodeUrl = chapterUrlList[i];
                if (!episodeUrl.startsWith('http')) {
                  if (episodeUrl.startsWith('/')) {
                    episodeUrl = '${rule.baseUrl}$episodeUrl';
                  } else {
                    episodeUrl = '${rule.baseUrl}/$episodeUrl';
                  }
                }
                
                AnimeEpisode episode = AnimeEpisode(
                  title: chapterNameList[i],
                  episodeUrl: episodeUrl,
                  episodeNumber: i + 1,
                  roadIndex: count - 1,
                );
                episodeList.add(episode);
              }
              count++;
            }
          } catch (e) {
            // Kazumi 使用空的 catch 块
          }
        });
      }
      
      Logger.info('找到 ${episodeList.length} 个章节');
      return episodeList;
    } catch (e) {
      Logger.error('获取章节失败: $e');
      return []; // 按照 Kazumi 的方式，返回空列表而不是抛出异常
    }
  }

  /// 调试搜索请求 - 用于测试有问题的规则
  Future<Map<String, dynamic>> debugSearchRequest(UnifiedRule rule, String keyword) async {
    try {
      Logger.info('调试搜索 - 规则: ${rule.name}, 关键词: $keyword');
      
      if (rule.searchConfig == null) {
        return {'error': '规则没有搜索配置'};
      }

      final searchConfig = rule.searchConfig!;
      String queryURL = searchConfig.searchUrl.replaceAll('@keyword', keyword);
      Logger.info('搜索URL: $queryURL');
      
      // 检查URL是否有效
      try {
        Uri.parse(queryURL);
      } catch (e) {
        return {'error': '无效的搜索URL: $queryURL'};
      }
      
      dynamic resp;
      
      // 添加短暂延迟
      await Future.delayed(Duration(milliseconds: 200));

      try {
        if (searchConfig.usePost) {
          Logger.info('使用 POST 请求...');
          Uri uri = Uri.parse(queryURL);
          Map<String, String> queryParams = uri.queryParameters;
          Uri postUri = Uri(
            scheme: uri.scheme,
            host: uri.host,
            path: uri.path,
          );
          
          var httpHeaders = {
            'referer': '${rule.baseUrl}/',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept-Language': _getRandomAcceptedLanguage(),
            'Connection': 'keep-alive',
          };
          
          resp = await _dio.post(
            postUri.toString(),
            options: Options(headers: httpHeaders),
            data: queryParams,
          );
        } else {
          Logger.info('使用 GET 请求...');
          var httpHeaders = {
            'referer': '${rule.baseUrl}/',
            'Accept-Language': _getRandomAcceptedLanguage(),
            'Connection': 'keep-alive',
          };
          
          resp = await _dio.get(
            queryURL,
            options: Options(
              headers: httpHeaders,
              responseType: ResponseType.plain, // 改回plain，让Dio自动处理解压缩
            ),
          );
        }
      } catch (e) {
        return {
          'error': '网络请求失败',
          'details': e.toString(),
          'url': queryURL,
        };
      }

      Logger.info('收到响应，状态码: ${resp.statusCode}');
      
      // 直接使用响应数据，Dio已经自动处理了gzip解压缩和编码
      String htmlString = resp.data.toString();
      Logger.info('响应内容长度: ${htmlString.length} 字符');
      
      // 返回调试信息
      Map<String, dynamic> debugInfo = {
        'url': queryURL,
        'statusCode': resp.statusCode,
        'contentLength': htmlString.length,
        'searchList': searchConfig.searchList ?? '',
        'searchName': searchConfig.searchName ?? '',
        'searchResult': searchConfig.searchResult ?? '',
        'usePost': searchConfig.usePost,
      };
      
      // 检查内容是否被拦截
      if (htmlString.length < 100) {
        debugInfo['warning'] = '响应内容过短，可能被拦截';
      }
      
      // 尝试解析HTML
      try {
        var htmlElement = parse(htmlString).documentElement!;
        
        // 测试选择器
        final searchListSelector = searchConfig.searchList ?? '';
        if (searchListSelector.isNotEmpty) {
          final searchListNodes = htmlElement.queryXPath(searchListSelector).nodes;
          debugInfo['searchListNodesCount'] = searchListNodes.length;
          
          if (searchListNodes.isNotEmpty) {
            // 测试第一个节点的子选择器
            final firstNode = searchListNodes.first;
            final nameSelector = searchConfig.searchName ?? '';
            final resultSelector = searchConfig.searchResult ?? '';
            
            if (nameSelector.isNotEmpty) {
              try {
                final nameNode = firstNode.queryXPath(nameSelector).node;
                debugInfo['firstItemName'] = nameNode?.text?.trim() ?? '(空)';
              } catch (e) {
                debugInfo['nameSelectionError'] = e.toString();
              }
            }
            
            if (resultSelector.isNotEmpty) {
              try {
                final resultNode = firstNode.queryXPath(resultSelector).node;
                debugInfo['firstItemUrl'] = resultNode?.attributes['href'] ?? '(空)';
              } catch (e) {
                debugInfo['resultSelectionError'] = e.toString();
              }
            }
          }
        } else {
          debugInfo['warning'] = '搜索列表选择器为空';
        }
        
        // 保存部分HTML内容用于调试
        debugInfo['htmlPreview'] = htmlString.length > 1000 
          ? htmlString.substring(0, 1000) + '...' 
          : htmlString;
          
      } catch (e) {
        debugInfo['parseError'] = e.toString();
      }
      
      return debugInfo;
    } catch (e) {
      return {
        'error': '调试失败',
        'details': e.toString(),
      };
    }
  }
}