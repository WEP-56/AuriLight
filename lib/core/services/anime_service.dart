import '../models/unified_rule.dart';
import '../models/anime_item.dart';
import '../utils/logger.dart';
import 'kazumi_network_service.dart';

/// 动漫服务 - 处理动漫相关的业务逻辑
class AnimeService {
  static final AnimeService _instance = AnimeService._internal();
  factory AnimeService() => _instance;
  AnimeService._internal();

  final KazumiNetworkService _networkService = KazumiNetworkService();

  /// 搜索动漫
  Future<List<AnimeItem>> searchAnime(UnifiedRule rule, String keyword) async {
    return await _networkService.searchAnime(rule, keyword);
  }

  /// 测试规则的搜索功能 - 用于调试
  Future<Map<String, dynamic>> testRuleSearch(UnifiedRule rule, String keyword) async {
    try {
      Logger.info('测试规则搜索功能 - 规则: ${rule.name}, 关键词: $keyword');
      
      // 获取原始HTML响应
      final htmlString = await _networkService.testSearchRequest(rule, keyword);
      
      // 测试XPath选择器
      final xpathResult = _networkService.testXPathSelectors(htmlString, rule);
      
      // 尝试正常搜索
      final searchResult = await _networkService.searchAnime(rule, keyword);
      
      return {
        'rule': rule.name,
        'keyword': keyword,
        'htmlLength': htmlString.length,
        'htmlString': htmlString, // 添加HTML内容
        'xpathTest': xpathResult,
        'searchResults': searchResult.length,
        'success': true,
      };
    } catch (e) {
      Logger.error('测试规则搜索失败: $e');
      return {
        'rule': rule.name,
        'keyword': keyword,
        'error': e.toString(),
        'success': false,
      };
    }
  }

  /// 获取动漫详情
  Future<AnimeDetail?> getAnimeDetail(UnifiedRule rule, String detailUrl) async {
    try {
      Logger.info('Getting anime detail: $detailUrl');

      // 获取章节列表
      final episodes = await _networkService.getEpisodes(rule, detailUrl);

      // 从URL或其他方式提取标题（简化实现）
      String title = 'Unknown';
      // 这里可以根据需要解析详情页面获取更多信息

      return AnimeDetail(
        title: title,
        coverUrl: null,
        description: null,
        detailUrl: detailUrl,
        episodes: episodes,
        ruleName: rule.name,
        ruleKey: rule.key,
      );
    } catch (e) {
      Logger.error('Failed to get anime detail: $e');
      return null;
    }
  }

  /// 获取播放链接
  Future<String?> getPlayUrl(UnifiedRule rule, String episodeUrl) async {
    try {
      Logger.info('Getting play URL: $episodeUrl');

      // 暂时返回原始URL，后续可以根据需要扩展
      return episodeUrl;
    } catch (e) {
      Logger.error('Failed to get play URL: $e');
      return null;
    }
  }

  /// 测试规则
  Future<String> testRule(UnifiedRule rule, String keyword) async {
    return await _networkService.testSearchRequest(rule, keyword);
  }
}