import 'package:dio/dio.dart';

import '../models/bangumi_item.dart';
import '../utils/logger.dart';

/// Bangumi服务 - 基于Kazumi的BangumiHTTP实现
class BangumiService {
  static final BangumiService _instance = BangumiService._internal();
  factory BangumiService() => _instance;
  BangumiService._internal();

  Dio? _dio;
  bool _initialized = false;

  /// Bangumi API域名
  static const String bangumiAPIDomain = 'https://api.bgm.tv';
  static const String bangumiAPINextDomain = 'https://next.bgm.tv';

  /// API端点
  static const String bangumiInfoByID = '/v0/subjects/{0}';
  static const String bangumiRankSearch = '/v0/search/subjects?limit={0}&offset={1}';

  /// 初始化服务
  void initialize() {
    if (_initialized) return; // 避免重复初始化
    
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 12000),
      receiveTimeout: const Duration(milliseconds: 12000),
      sendTimeout: const Duration(milliseconds: 10000),
      headers: {
        'User-Agent': 'AuriLight/1.0.0',
      },
    ));

    // 添加日志拦截器
    _dio!.interceptors.add(LogInterceptor(
      request: false,
      requestHeader: false,
      responseHeader: false,
    ));
    
    _initialized = true;
  }

  /// 获取Dio实例
  Dio get dio {
    if (!_initialized) initialize();
    return _dio!;
  }

  /// 格式化URL
  String _formatUrl(String url, List<dynamic> params) {
    for (int i = 0; i < params.length; i++) {
      url = url.replaceAll('{$i}', params[i].toString());
    }
    return url;
  }

  /// 通过关键词搜索Bangumi
  Future<List<BangumiItem>> searchBangumi(String keyword, {
    List<String> tags = const [],
    int offset = 0,
    String sort = 'heat'
  }) async {
    List<BangumiItem> bangumiList = [];

    var params = <String, dynamic>{
      'keyword': keyword,
      'sort': sort,
      "filter": {
        "type": [2], // 动画类型
        "tag": tags,
        "rank": (sort == 'rank') ? [">0", "<=99999"] : [">=0", "<=99999"],
        "nsfw": false
      },
    };

    try {
      Logger.info('搜索Bangumi: $keyword');
      
      final url = _formatUrl(bangumiAPIDomain + bangumiRankSearch, [20, offset]);
      final res = await dio.post(url, data: params);
      
      final jsonData = res.data;
      final jsonList = jsonData['data'];
      
      for (dynamic jsonItem in jsonList) {
        if (jsonItem is Map<String, dynamic>) {
          try {
            BangumiItem bangumiItem = BangumiItem.fromJson(jsonItem);
            if (bangumiItem.displayName.isNotEmpty) {
              bangumiList.add(bangumiItem);
            }
          } catch (e) {
            Logger.error('解析Bangumi搜索结果失败: $e');
          }
        }
      }
      
      Logger.info('Bangumi搜索完成，找到 ${bangumiList.length} 个结果');
    } catch (e) {
      Logger.error('Bangumi搜索失败: $e');
    }
    
    return bangumiList;
  }

  /// 通过ID获取Bangumi详细信息
  Future<BangumiItem?> getBangumiById(int id) async {
    try {
      Logger.info('获取Bangumi详情: $id');
      
      final url = _formatUrl(bangumiAPIDomain + bangumiInfoByID, [id]);
      final res = await dio.get(url);
      
      final bangumiItem = BangumiItem.fromJson(res.data);
      Logger.info('Bangumi详情获取成功: ${bangumiItem.displayName}');
      
      return bangumiItem;
    } catch (e) {
      Logger.error('获取Bangumi详情失败: $e');
      return null;
    }
  }

  /// 通过动漫名称匹配Bangumi信息
  /// 这是核心功能：将规则源的动漫与Bangumi数据库匹配
  Future<BangumiItem?> matchAnimeWithBangumi(String animeName) async {
    try {
      Logger.info('尝试匹配动漫与Bangumi: $animeName');
      
      // 清理动漫名称，移除常见的后缀和特殊字符
      String cleanName = _cleanAnimeName(animeName);
      
      // 搜索Bangumi
      final searchResults = await searchBangumi(cleanName, sort: 'rank');
      
      if (searchResults.isEmpty) {
        Logger.info('未找到匹配的Bangumi: $animeName');
        return null;
      }
      
      // 寻找最佳匹配
      BangumiItem? bestMatch = _findBestMatch(animeName, searchResults);
      
      if (bestMatch != null) {
        Logger.info('找到最佳匹配: ${animeName} -> ${bestMatch.displayName}');
        
        // 获取完整详情
        return await getBangumiById(bestMatch.id);
      }
      
      Logger.info('未找到合适的匹配: $animeName');
      return null;
    } catch (e) {
      Logger.error('匹配Bangumi失败: $e');
      return null;
    }
  }

  /// 清理动漫名称
  String _cleanAnimeName(String name) {
    // 移除常见的后缀
    final suffixes = [
      '第一季', '第二季', '第三季', '第四季', '第五季',
      '第1季', '第2季', '第3季', '第4季', '第5季',
      'Season 1', 'Season 2', 'Season 3', 'Season 4', 'Season 5',
      'S1', 'S2', 'S3', 'S4', 'S5',
      'OVA', 'OAD', 'SP', '特别篇', '剧场版',
      '(TV)', '(OVA)', '(Movie)',
    ];
    
    String cleaned = name.trim();
    
    for (String suffix in suffixes) {
      if (cleaned.endsWith(suffix)) {
        cleaned = cleaned.substring(0, cleaned.length - suffix.length).trim();
      }
    }
    
    // 移除括号内容
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '').trim();
    
    return cleaned;
  }

  /// 寻找最佳匹配
  BangumiItem? _findBestMatch(String targetName, List<BangumiItem> candidates) {
    if (candidates.isEmpty) return null;
    
    String cleanTarget = _cleanAnimeName(targetName).toLowerCase();
    
    // 精确匹配
    for (BangumiItem item in candidates) {
      if (_cleanAnimeName(item.name).toLowerCase() == cleanTarget ||
          _cleanAnimeName(item.nameCn).toLowerCase() == cleanTarget) {
        return item;
      }
      
      // 检查别名
      for (String alias in item.alias) {
        if (_cleanAnimeName(alias).toLowerCase() == cleanTarget) {
          return item;
        }
      }
    }
    
    // 包含匹配
    for (BangumiItem item in candidates) {
      String itemName = _cleanAnimeName(item.displayName).toLowerCase();
      if (itemName.contains(cleanTarget) || cleanTarget.contains(itemName)) {
        return item;
      }
    }
    
    // 如果没有找到好的匹配，返回排名最高的
    candidates.sort((a, b) => a.rank.compareTo(b.rank));
    return candidates.first;
  }
}