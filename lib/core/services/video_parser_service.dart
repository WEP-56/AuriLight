import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:kazuvera2d/core/services/simple_webview_parser.dart';
import 'package:flutter/material.dart';

/// 视频URL解析结果
class VideoParseResult {
  final String? videoUrl;
  final Map<String, String> httpHeaders;
  final String? proxyUrl; // 添加代理URL

  VideoParseResult({
    this.videoUrl,
    this.httpHeaders = const {},
    this.proxyUrl,
  });
}

/// 视频URL解析服务
class VideoParserService {
  static final Dio _dio = Dio();

  /// 清理和标准化URL
  static String _cleanUrl(String url) {
    // 首先处理JSON转义的反斜杠
    String cleaned = url.replaceAll(r'\/', '/');
    
    // 处理Unicode转义字符
    cleaned = _decodeUnicodeEscapes(cleaned);
    
    // 检查URL是否已经被编码过，如果是则不再编码
    if (!_isAlreadyEncoded(cleaned)) {
      // 只对中文字符进行URL编码
      cleaned = _encodeChineseCharactersOnly(cleaned);
    }
    
    // 移除多余的斜杠，但保留协议部分的双斜杠
    cleaned = cleaned.replaceAllMapped(
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

  /// 检查URL是否已经被编码
  static bool _isAlreadyEncoded(String url) {
    return url.contains('%') && RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(url);
  }

  /// 只对中文字符进行URL编码，保持其他部分不变
  static String _encodeChineseCharactersOnly(String input) {
    return input.replaceAllMapped(
      RegExp(r'[\u4e00-\u9fff]+'), // 匹配中文字符
      (match) => Uri.encodeComponent(match.group(0)!),
    );
  }

  /// 解码Unicode转义字符
  static String _decodeUnicodeEscapes(String input) {
    return input.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) {
        final hexCode = match.group(1)!;
        final charCode = int.parse(hexCode, radix: 16);
        return String.fromCharCode(charCode);
      },
    );
  }

  /// 从剧集页面URL解析出真实的视频流URL和所需的HTTP头
  static Future<VideoParseResult> parseVideoUrl(String episodeUrl, {Map<String, dynamic>? ruleConfig, BuildContext? context}) async {
    try {
      // 清理输入URL
      episodeUrl = _cleanUrl(episodeUrl);
      print('清理后的URL: $episodeUrl');
      
      // 测试用：如果URL已经是视频文件，直接返回
      if (isDirectVideoUrl(episodeUrl)) {
        return VideoParseResult(videoUrl: episodeUrl);
      }
      
      // 检查是否需要使用WebView解析
      final bool useWebview = ruleConfig?['useWebview'] == true;
      if (useWebview && context != null) {
        print('规则要求使用WebView解析');
        
        // 检查平台是否支持WebView
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          print('桌面平台暂不支持WebView，使用HTML解析作为替代');
          return await _parseWithHtml(episodeUrl);
        }
        
        return await _parseWithWebView(episodeUrl, ruleConfig, context);
      }
      
      // 使用HTML解析
      return await _parseWithHtml(episodeUrl);
    } catch (e) {
      print('视频URL解析失败: $e');
      return VideoParseResult();
    }
  }

  /// 使用WebView解析视频URL
  static Future<VideoParseResult> _parseWithWebView(String episodeUrl, Map<String, dynamic>? ruleConfig, BuildContext context) async {
    try {
      // 检查平台支持
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        print('桌面平台不支持WebView，回退到HTML解析');
        return await _parseWithHtml(episodeUrl);
      }
      
      // 优先尝试无头解析（更快）
      String? videoUrl = await SimpleWebViewParser.parseVideoUrlHeadless(episodeUrl);
      
      // 如果无头解析失败，尝试有UI的解析
      if (videoUrl == null || videoUrl.isEmpty) {
        print('无头WebView解析失败，尝试有UI解析');
        // 在async操作前检查context是否仍然mounted
        if (context.mounted) {
          videoUrl = await SimpleWebViewParser.parseVideoUrl(episodeUrl, context);
        }
      }
      
      if (videoUrl != null && videoUrl.isNotEmpty) {
        // 为视频URL生成HTTP头
        final videoHeaders = _getHttpHeadersForVideoUrl(videoUrl, episodeUrl);
        
        return VideoParseResult(
          videoUrl: videoUrl,
          httpHeaders: videoHeaders,
        );
      }
      
      print('WebView解析未找到视频URL');
      return VideoParseResult();
    } catch (e) {
      print('WebView解析失败: $e');
      // 如果WebView解析失败，回退到HTML解析
      return await _parseWithHtml(episodeUrl);
    }
  }

  /// 使用HTML解析视频URL
  static Future<VideoParseResult> _parseWithHtml(String episodeUrl, {int depth = 0}) async {
    // 防止无限递归
    if (depth > 2) {
      print('递归深度超限，停止解析');
      return VideoParseResult();
    }
    try {
      // 清理输入URL
      episodeUrl = _cleanUrl(episodeUrl);
      print('清理后的URL: $episodeUrl');
      
      // 测试用：如果URL已经是视频文件，直接返回
      if (isDirectVideoUrl(episodeUrl)) {
        return VideoParseResult(videoUrl: episodeUrl);
      }
      
      // 根据域名确定需要的HTTP头
      final httpHeaders = _getHttpHeadersForDomain(episodeUrl);
      
      // 获取剧集页面HTML
      final response = await _dio.get(
        episodeUrl,
        options: Options(
          headers: {
            'User-Agent': httpHeaders['user-agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Referer': httpHeaders['referer'] ?? _getBaseUrl(episodeUrl),
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
          followRedirects: true,
          validateStatus: (status) => status! < 500,
        ),
      );
      
      print('页面响应状态: ${response.statusCode}');
      print('页面内容长度: ${response.data.toString().length}');
      
      final document = html_parser.parse(response.data);

      // 尝试多种常见的视频URL提取方式
      String? videoUrl = await _extractVideoUrl(document, episodeUrl, depth: depth);
      
      if (videoUrl != null && videoUrl != episodeUrl) {
        // 清理提取到的URL
        videoUrl = _cleanUrl(videoUrl);
        
        // 如果是相对URL，转换为绝对URL
        if (videoUrl.startsWith('/')) {
          final uri = Uri.parse(episodeUrl);
          videoUrl = '${uri.scheme}://${uri.host}$videoUrl';
        } else if (!videoUrl.startsWith('http')) {
          final uri = Uri.parse(episodeUrl);
          final basePath = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
          videoUrl = '${uri.scheme}://${uri.host}$basePath$videoUrl';
        }
        
        // 再次清理最终URL
        videoUrl = _cleanUrl(videoUrl);
        print('最终视频URL: $videoUrl');
        
        // 验证是否是有效的视频URL
        if (isDirectVideoUrl(videoUrl)) {
          // 为视频URL生成HTTP头
          final videoHeaders = _getHttpHeadersForVideoUrl(videoUrl, episodeUrl);
          
          return VideoParseResult(
            videoUrl: videoUrl,
            httpHeaders: videoHeaders,
          );
        } else {
          print('提取的URL不是有效的视频格式: $videoUrl');
        }
      }

      // 如果HTML解析失败，可能需要WebView
      print('HTML解析未找到视频URL，可能需要WebView解析');
      return VideoParseResult();
    } catch (e) {
      print('视频URL解析失败: $e');
      return VideoParseResult();
    }
  }

  /// 根据域名获取HTTP头信息
  static Map<String, String> _getHttpHeadersForDomain(String url) {
    final uri = Uri.parse(url);
    final domain = uri.host.toLowerCase();
    
    // 根据不同的域名返回相应的HTTP头
    if (domain.contains('libvio.cc')) {
      return {
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'referer': 'https://www.libvio.cc/',
      };
    } else if (domain.contains('ylys.cc')) {
      return {
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'referer': 'https://www.ylys.cc/',
      };
    }
    
    // 默认HTTP头
    return {
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      'referer': _getBaseUrl(url),
    };
  }

  /// 为视频URL生成HTTP头信息
  static Map<String, String> _getHttpHeadersForVideoUrl(String videoUrl, String pageUrl) {
    final videoUri = Uri.parse(videoUrl);
    final pageUri = Uri.parse(pageUrl);
    
    // 如果视频和页面在同一域名，使用页面作为referer
    if (videoUri.host == pageUri.host) {
      return _getHttpHeadersForDomain(pageUrl);
    }
    
    // 根据视频域名特殊处理
    final videoDomain = videoUri.host.toLowerCase();
    
    if (videoDomain.contains('vbing.me')) {
      return {
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'referer': pageUrl, // 使用页面URL作为referer
      };
    }
    
    // 默认使用页面的HTTP头配置
    return _getHttpHeadersForDomain(pageUrl);
  }

  /// 获取URL的基础部分
  static String _getBaseUrl(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}/';
  }

  /// 从HTML文档中提取视频URL
  static Future<String?> _extractVideoUrl(Document document, String pageUrl, {int depth = 0}) async {
    print('开始从HTML中提取视频URL...');
    
    // 方法1: 查找video标签的src属性
    final videoElements = document.querySelectorAll('video');
    print('发现video标签数量: ${videoElements.length}');
    for (final video in videoElements) {
      final src = video.attributes['src'];
      if (src != null && src.isNotEmpty && isDirectVideoUrl(src)) {
        print('从video标签找到src: $src');
        return src;
      }
    }

    // 方法2: 查找source标签的src属性
    final sourceElements = document.querySelectorAll('source');
    print('发现source标签数量: ${sourceElements.length}');
    for (final source in sourceElements) {
      final src = source.attributes['src'];
      if (src != null && src.isNotEmpty && isDirectVideoUrl(src)) {
        print('从source标签找到src: $src');
        return src;
      }
    }

    // 方法3: 在script标签中查找视频URL
    final scriptElements = document.querySelectorAll('script');
    print('发现script标签数量: ${scriptElements.length}');
    for (final script in scriptElements) {
      final content = script.text;
      
      // 优先查找直接的视频文件URL
      final directVideoPatterns = [
        RegExp(r'"(https?://[^"]*\.(?:mp4|m3u8|flv|avi|mkv|webm)[^"]*)"'),
        RegExp(r"'(https?://[^']*\.(?:mp4|m3u8|flv|avi|mkv|webm)[^']*)'"),
      ];

      for (final pattern in directVideoPatterns) {
        final matches = pattern.allMatches(content);
        for (final match in matches) {
          String url = match.group(1)!;
          if (_isValidVideoUrl(url)) {
            print('从script中找到直接视频URL: $url');
            return url;
          }
        }
      }
      
      // 查找播放器配置中的URL
      final configPatterns = [
        // 标准配置格式
        RegExp(r'url["\s]*:["\s]*"([^"]*)"'),
        RegExp(r"url['\s]*:['\s]*'([^']*)'"),
        RegExp(r'src["\s]*:["\s]*"([^"]*)"'),
        RegExp(r"src['\s]*:['\s]*'([^']*)'"),
        RegExp(r'file["\s]*:["\s]*"([^"]*)"'),
        RegExp(r"file['\s]*:['\s]*'([^']*)'"),
        
        // 播放器对象中的URL（更具体的匹配）
        RegExp(r'player_aaaa\s*=\s*\{[^}]*"url"\s*:\s*"([^"]*)"'),
        RegExp(r"player_aaaa\s*=\s*\{[^}]*'url'\s*:\s*'([^']*)'"),
        RegExp(r'player[^{]*\{[^}]*"url"\s*:\s*"([^"]*)"'),
        RegExp(r"player[^{]*\{[^}]*'url'\s*:\s*'([^']*)'"),
      ];

      for (final pattern in configPatterns) {
        final matches = pattern.allMatches(content);
        for (final match in matches) {
          String url = match.group(1)!;
          
          // 跳过明显不是视频的URL
          if (_shouldSkipUrl(url)) continue;
          
          // 只对可能的视频URL进行解码
          if (url.length > 50 && (url.contains('%') || RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(url))) {
            // 尝试解码URL（处理各种编码格式）
            String decodedUrl = _tryDecodeUrl(url);
            print('原始URL: $url');
            print('解码后URL: $decodedUrl');
            
            if (isDirectVideoUrl(decodedUrl)) {
              print('从script配置中找到直接视频URL: $decodedUrl');
              return decodedUrl;
            } else if (_couldBeVideoUrl(decodedUrl)) {
              print('从script配置中找到可能的视频URL: $decodedUrl');
              return decodedUrl;
            } else if (decodedUrl.contains('/play/') && decodedUrl != pageUrl) {
              // 如果解码后是另一个播放页面URL，且不是当前页面，递归解析
              print('解码后是播放页面URL，尝试递归解析: $decodedUrl');
              try {
                final recursiveResult = await _parseWithHtml(decodedUrl, depth: depth + 1);
                if (recursiveResult.videoUrl != null) {
                  print('递归解析成功: ${recursiveResult.videoUrl}');
                  return recursiveResult.videoUrl;
                }
              } catch (e) {
                print('递归解析失败: $e');
              }
            }
          }
          
          // 如果是直接的视频URL，直接返回
          if (isDirectVideoUrl(url) || _couldBeVideoUrl(url)) {
            print('从script配置中找到视频URL: $url');
            return url;
          }
        }
      }
      
      // 如果script内容包含可能的视频相关信息，打印调试信息
      if (content.contains('.m3u8') || 
          content.contains('.mp4') || 
          content.contains('player') ||
          content.contains('video')) {
        final preview = content.length > 200 ? '${content.substring(0, 200)}...' : content;
        print('Script内容片段: $preview');
        
        // 如果包含player_aaaa，进行详细调试
        if (content.contains('player_aaaa')) {
          debugRegexMatching(content);
        }
      }
    }

    // 方法4: 查找iframe中的视频
    final iframeElements = document.querySelectorAll('iframe');
    print('发现iframe标签数量: ${iframeElements.length}');
    for (final iframe in iframeElements) {
      final src = iframe.attributes['src'];
      if (src != null && (src.contains('player') || src.contains('video'))) {
        print('从iframe找到播放器URL: $src');
        return src;
      }
    }

    print('未找到任何视频URL');
    return null;
  }

  /// 检查是否应该跳过这个URL
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
    ];
    
    return skipPatterns.any((pattern) => url.contains(pattern));
  }

  /// 检查URL是否可能是视频URL（但不是直接的视频文件）
  static bool _couldBeVideoUrl(String url) {
    // Base64编码的可能性
    if (RegExp(r'^[A-Za-z0-9+/=]{30,}$').hasMatch(url)) {
      return true;
    }
    
    // 包含视频相关路径
    final videoPathPatterns = [
      RegExp(r'\/play\/'),
      RegExp(r'\/video\/'),
      RegExp(r'\/stream\/'),
      RegExp(r'\/vod\/'),
    ];
    
    return videoPathPatterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 验证提取的URL是否有效
  static bool _isValidVideoUrl(String url) {
    // 跳过明显无效的URL
    if (_shouldSkipUrl(url)) return false;
    
    // 检查是否是直接视频文件
    if (isDirectVideoUrl(url)) return true;
    
    // 检查是否可能是视频URL
    return _couldBeVideoUrl(url);
  }

  /// 调试方法：测试正则表达式匹配
  static void debugRegexMatching(String content) {
    print('=== 调试正则表达式匹配 ===');
    print('内容长度: ${content.length}');
    
    // 测试player_aaaa匹配
    final playerRegex = RegExp(r'player_aaaa\s*=\s*\{[^}]*"url"\s*:\s*"([^"]*)"');
    final playerMatch = playerRegex.firstMatch(content);
    if (playerMatch != null) {
      print('player_aaaa匹配成功: ${playerMatch.group(1)}');
    } else {
      print('player_aaaa匹配失败');
      
      // 尝试更简单的匹配
      final simpleRegex = RegExp(r'"url"\s*:\s*"([^"]*)"');
      final simpleMatches = simpleRegex.allMatches(content);
      print('简单url匹配数量: ${simpleMatches.length}');
      for (final match in simpleMatches) {
        print('  - ${match.group(1)}');
      }
    }
    
    print('=== 调试结束 ===');
  }

  /// 尝试解码URL（处理各种编码格式）
  static String _tryDecodeUrl(String url) {
    print('开始解码URL: $url');
    
    try {
      // 1. 尝试URL解码
      String decoded = Uri.decodeComponent(url);
      print('URL解码结果: $decoded');
      if (decoded != url && isDirectVideoUrl(decoded)) {
        print('URL解码成功: $decoded');
        return decoded;
      }
      
      // 2. 尝试Base64解码（只对明显的Base64字符串进行解码）
      if (_isLikelyBase64(url)) {
        try {
          print('尝试Base64解码...');
          
          // 先进行URL解码，因为Base64可能被URL编码了
          String urlDecoded = Uri.decodeComponent(url);
          print('URL解码后的Base64: $urlDecoded');
          
          // 处理URL安全的Base64编码
          String base64Url = urlDecoded.replaceAll('-', '+').replaceAll('_', '/');
          
          // 添加必要的填充
          while (base64Url.length % 4 != 0) {
            base64Url += '=';
          }
          
          print('处理后的Base64字符串: $base64Url');
          
          final bytes = base64Decode(base64Url);
          
          // 尝试UTF-8解码
          try {
            final decodedString = utf8.decode(bytes);
            print('Base64解码结果: $decodedString');
            
            // 关键修复：如果Base64解码结果是URL编码的，再次进行URL解码
            String finalDecoded = decodedString;
            if (decodedString.contains('%')) {
              try {
                finalDecoded = Uri.decodeComponent(decodedString);
                print('Base64解码后再次URL解码: $finalDecoded');
              } catch (e) {
                print('Base64解码结果URL解码失败: $e');
                // 使用原始解码结果
              }
            }
            
            if (isDirectVideoUrl(finalDecoded)) {
              print('Base64解码成功: $finalDecoded');
              return finalDecoded;
            }
            
            // 如果解码结果不是直接视频URL，但可能是视频相关URL，也返回
            if (_couldBeVideoUrl(finalDecoded)) {
              print('Base64解码得到可能的视频URL: $finalDecoded');
              return finalDecoded;
            }
          } catch (e) {
            print('UTF-8解码失败，可能是二进制数据: $e');
            // 对于二进制数据，不进行解码，直接返回原URL
            print('跳过二进制数据的解码');
          }
          
        } catch (e) {
          print('Base64解码失败: $e');
        }
      }
      
      // 3. 尝试双重URL解码（有些网站会进行多次编码）
      try {
        String doubleDecoded = Uri.decodeComponent(Uri.decodeComponent(url));
        print('双重URL解码结果: $doubleDecoded');
        if (doubleDecoded != decoded && isDirectVideoUrl(doubleDecoded)) {
          print('双重URL解码成功: $doubleDecoded');
          return doubleDecoded;
        }
      } catch (e) {
        print('双重解码失败: $e');
      }
      
      print('所有解码尝试都失败，返回原始URL');
      return url; // 如果所有解码都失败，返回原始URL
    } catch (e) {
      print('解码过程出错: $e');
      return url; // 解码出错，返回原始URL
    }
  }

  /// 检查字符串是否可能是Base64编码
  static bool _isLikelyBase64(String str) {
    // 基本长度检查
    if (str.length < 20) return false;
    
    // 检查是否只包含Base64字符
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=%_-]+$');
    if (!base64Pattern.hasMatch(str)) return false;
    
    // 检查长度是否符合Base64规则（4的倍数，允许填充）
    final cleanStr = str.replaceAll(RegExp(r'[=%]'), '');
    return cleanStr.length >= 16; // 至少16个字符才考虑Base64
  }

  /// 检查URL是否为直接的视频文件URL
  static bool isDirectVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.m3u8', '.flv', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => url.toLowerCase().contains(ext));
  }

  /// 检查URL是否为有效的视频流（更宽松的检查，用于向后兼容）
  static bool isValidVideoUrl(String url) {
    // 首先检查是否是直接视频文件
    if (isDirectVideoUrl(url)) {
      return true;
    }
    
    // 检查是否是可能的视频URL模式
    final videoPatterns = [
      RegExp(r'\/play\/.*'), // 播放页面路径
      RegExp(r'\/video\/.*'), // 视频路径
      RegExp(r'\/stream\/.*'), // 流媒体路径
      RegExp(r'[a-zA-Z0-9+/=]{20,}'), // Base64编码的可能性
    ];
    
    return videoPatterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 获取视频流的直接播放URL（处理重定向等）
  static Future<String?> getDirectVideoUrl(String videoUrl) async {
    try {
      final response = await _dio.head(videoUrl);
      
      // 检查是否有重定向
      if (response.redirects.isNotEmpty) {
        return response.redirects.last.location.toString();
      }
      
      return videoUrl;
    } catch (e) {
      print('获取直接视频URL失败: $e');
      return videoUrl; // 返回原URL作为fallback
    }
  }
}