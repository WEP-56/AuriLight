import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

import '../utils/logger.dart';

/// 网络服务 - 处理HTTP请求和HTML解析
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  late final Dio _dio;

  /// 初始化网络服务
  void initialize() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      },
    ));

    // 添加拦截器用于日志记录
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (obj) => Logger.info(obj.toString()),
    ));
  }

  /// 发送GET请求
  Future<String> get(String url, {Map<String, String>? headers}) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(headers: headers),
      );
      return response.data.toString();
    } catch (e) {
      Logger.error('GET request failed for $url: $e');
      rethrow;
    }
  }

  /// 发送POST请求
  Future<String> post(
    String url, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );
      return response.data.toString();
    } catch (e) {
      Logger.error('POST request failed for $url: $e');
      rethrow;
    }
  }

  /// 解析HTML并使用XPath选择器
  List<html_dom.Element> parseHtmlWithXPath(String html, String xpath) {
    try {
      final document = html_parser.parse(html);
      
      // 简化的XPath解析 - 这里需要一个更完整的XPath解析器
      // 暂时支持基本的XPath语法
      return _parseBasicXPath(document, xpath);
    } catch (e) {
      Logger.error('HTML parsing failed with XPath $xpath: $e');
      return [];
    }
  }

  /// 解析HTML并使用CSS选择器
  List<html_dom.Element> parseHtmlWithCss(String html, String cssSelector) {
    try {
      final document = html_parser.parse(html);
      return document.querySelectorAll(cssSelector);
    } catch (e) {
      Logger.error('HTML parsing failed with CSS selector $cssSelector: $e');
      return [];
    }
  }

  /// 基础XPath解析器 - 支持常见的XPath语法
  List<html_dom.Element> _parseBasicXPath(html_dom.Document document, String xpath) {
    // 移除开头的 //
    String cleanXPath = xpath.startsWith('//') ? xpath.substring(2) : xpath;
    
    // 分割路径
    List<String> parts = cleanXPath.split('/');
    List<html_dom.Element> currentElements = [document.documentElement!];
    
    for (String part in parts) {
      if (part.isEmpty) continue;
      
      List<html_dom.Element> nextElements = [];
      
      for (html_dom.Element element in currentElements) {
        if (part.contains('[') && part.contains(']')) {
          // 处理带属性或索引的选择器
          nextElements.addAll(_parseXPathWithPredicate(element, part));
        } else if (part.contains('@')) {
          // 处理属性选择器
          nextElements.addAll(_parseXPathAttribute(element, part));
        } else {
          // 简单标签选择器
          nextElements.addAll(element.querySelectorAll(part));
        }
      }
      
      currentElements = nextElements;
    }
    
    return currentElements;
  }

  /// 解析带谓词的XPath（如 div[@class='test'] 或 div[2]）
  List<html_dom.Element> _parseXPathWithPredicate(html_dom.Element element, String part) {
    final predicateMatch = RegExp(r'(\w+)\[([^\]]+)\]').firstMatch(part);
    if (predicateMatch == null) return [];
    
    final tagName = predicateMatch.group(1)!;
    final predicate = predicateMatch.group(2)!;
    
    List<html_dom.Element> elements = element.querySelectorAll(tagName);
    
    if (predicate.startsWith('@')) {
      // 属性谓词 @class='value' 或 @class="value"
      RegExp attrMatch;
      if (predicate.contains("'")) {
        attrMatch = RegExp(r"@(\w+)='([^']+)'");
      } else {
        attrMatch = RegExp(r'@(\w+)="([^"]+)"');
      }
      final match = attrMatch.firstMatch(predicate);
      if (match != null) {
        final attrName = match.group(1)!;
        final attrValue = match.group(2)!;
        return elements.where((e) => e.attributes[attrName] == attrValue).toList();
      }
    } else if (RegExp(r'^\d+$').hasMatch(predicate)) {
      // 索引谓词
      final index = int.parse(predicate) - 1; // XPath索引从1开始
      return index < elements.length ? [elements[index]] : [];
    }
    
    return elements;
  }

  /// 解析XPath属性选择器（如 @href）
  List<html_dom.Element> _parseXPathAttribute(html_dom.Element element, String part) {
    // 对于属性选择器，返回包含该属性的元素
    if (part.startsWith('@')) {
      final attrName = part.substring(1);
      return element.querySelectorAll('*').where((e) => e.attributes.containsKey(attrName)).toList();
    }
    return [];
  }

  /// 从元素中提取文本内容
  String extractText(html_dom.Element element) {
    return element.text.trim();
  }

  /// 从元素中提取属性值
  String? extractAttribute(html_dom.Element element, String attributeName) {
    return element.attributes[attributeName];
  }

  /// 从元素中提取href属性（常用于链接）
  String? extractHref(html_dom.Element element) {
    return element.attributes['href'];
  }

  /// 从元素中提取src属性（常用于图片）
  String? extractSrc(html_dom.Element element) {
    return element.attributes['src'];
  }

  /// 构建完整URL
  String buildFullUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http')) {
      return relativeUrl;
    }
    
    if (relativeUrl.startsWith('/')) {
      final uri = Uri.parse(baseUrl);
      return '${uri.scheme}://${uri.host}$relativeUrl';
    }
    
    return '$baseUrl/$relativeUrl';
  }
}