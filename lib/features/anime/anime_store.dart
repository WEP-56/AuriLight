import 'package:mobx/mobx.dart';

import '../../core/models/unified_rule.dart';
import '../../core/models/anime_item.dart';
import '../../core/models/unified_models.dart';
import '../../core/services/anime_service.dart';
import '../../core/services/bangumi_service.dart';
import '../../core/services/favorite_service.dart';
import '../../core/rule_engine/rule_manager.dart';
import '../../core/utils/logger.dart';

part 'anime_store.g.dart';

/// 动漫模块状态管理
class AnimeStore = _AnimeStoreBase with _$AnimeStore;

abstract class _AnimeStoreBase with Store {
  final AnimeService _animeService = AnimeService();
  final BangumiService _bangumiService = BangumiService();
  final RuleManager _ruleManager = RuleManager();
  final FavoriteService _favoriteService = FavoriteService();

  @observable
  bool isLoading = false;

  @observable
  bool isTestMode = false;

  @observable
  String? htmlContent;

  @observable
  String? error;

  @observable
  String searchKeyword = '';

  @observable
  ObservableList<AnimeItem> searchResults = ObservableList<AnimeItem>();

  @observable
  UnifiedRule? selectedRule;

  @observable
  bool enableBangumiIntegration = true; // 是否启用Bangumi集成

  @observable
  bool isFetchingBangumi = false; // 是否正在获取Bangumi信息

  @observable
  AnimeDetail? currentAnimeDetail;

  @computed
  List<UnifiedRule> get availableRules => _ruleManager.enabledAnimeRules;

  /// 初始化
  @action
  Future<void> initialize([String? ruleKey]) async {
    try {
      // 初始化Bangumi服务
      _bangumiService.initialize();
      
      // 确保RuleManager已经初始化
      if (_ruleManager.rules.isEmpty) {
        await _ruleManager.initialize();
      }
      
      // 清空之前的状态
      error = null;
      searchResults.clear();
      currentAnimeDetail = null;
      
      // 如果指定了规则key，选择对应的规则
      if (ruleKey != null) {
        final rule = _ruleManager.getRuleByKey(ruleKey);
        if (rule != null && rule.type == RuleType.anime) {
          selectedRule = rule;
          return; // 找到指定规则就返回
        }
      }
      
      // 如果没有选中规则，选择第一个可用的动漫规则
      if (selectedRule == null && availableRules.isNotEmpty) {
        selectedRule = availableRules.first;
      }
    } catch (e) {
      error = 'Failed to initialize anime store: $e';
      Logger.error(error!);
    }
  }

  /// 设置搜索关键词
  @action
  void setSearchKeyword(String keyword) {
    searchKeyword = keyword;
  }

  /// 选择规则源
  @action
  void selectRule(UnifiedRule rule) {
    selectedRule = rule;
    // 清空之前的搜索结果
    searchResults.clear();
    currentAnimeDetail = null;
  }

  /// 测试规则搜索功能 - 用于调试问题规则
  @action
  Future<void> testRuleSearch() async {
    if (selectedRule == null || searchKeyword.trim().isEmpty) {
      error = '请先选择规则并输入搜索关键词';
      return;
    }

    try {
      isLoading = true;
      error = null;
      htmlContent = null; // 清空之前的HTML内容
      
      Logger.info('开始测试规则: ${selectedRule!.name}');
      
      final testResult = await _animeService.testRuleSearch(selectedRule!, searchKeyword.trim());
      
      if (testResult['success'] == true) {
        Logger.info('测试结果: ${testResult.toString()}');
        
        // 保存HTML内容用于显示
        if (testResult['htmlString'] != null) {
          htmlContent = testResult['htmlString'] as String;
        }
        
        // 显示测试结果摘要
        final xpathTest = testResult['xpathTest'] as Map<String, dynamic>?;
        if (xpathTest != null) {
          final searchListResult = xpathTest['searchList'] as Map<String, dynamic>?;
          final searchNameResult = xpathTest['searchName'] as Map<String, dynamic>?;
          final searchResultResult = xpathTest['searchResult'] as Map<String, dynamic>?;
          
          String summary = '测试完成:\n';
          summary += '- HTML长度: ${testResult['htmlLength']} 字符\n';
          
          if (searchListResult != null) {
            summary += '- 搜索列表: ${searchListResult['success'] ? '✓' : '✗'} (${searchListResult['count']} 个节点)\n';
          }
          
          if (searchNameResult != null) {
            summary += '- 名称提取: ${searchNameResult['success'] ? '✓' : '✗'} ("${searchNameResult['text'] ?? searchNameResult['error']}")\n';
          }
          
          if (searchResultResult != null) {
            summary += '- 链接提取: ${searchResultResult['success'] ? '✓' : '✗'} ("${searchResultResult['href'] ?? searchResultResult['error']}")\n';
          }
          
          summary += '- 最终结果: ${testResult['searchResults']} 个项目';
          
          error = summary;
        } else {
          error = '测试完成，但XPath测试结果为空';
        }
      } else {
        error = '测试失败: ${testResult['error']}';
      }
    } catch (e) {
      Logger.error('测试规则搜索失败: $e');
      error = '测试失败: $e';
    } finally {
      isLoading = false;
    }
  }

  /// 搜索动漫
  @action
  Future<void> searchAnime() async {
    if (selectedRule == null || searchKeyword.trim().isEmpty) {
      return;
    }

    try {
      isLoading = true;
      error = null;
      searchResults.clear();

      Logger.info('Searching anime: $searchKeyword with rule: ${selectedRule!.name}');

      final results = await _animeService.searchAnime(selectedRule!, searchKeyword.trim());
      searchResults.addAll(results);

      Logger.info('Search completed, found ${results.length} results');
      
      // 如果搜索成功但没有结果，设置特殊的错误信息
      if (results.isEmpty) {
        error = '搜索完成，但没有找到相关结果。请尝试：\n• 更换关键词\n• 使用更简短的搜索词\n• 尝试其他规则源';
      } else {
        // 异步获取Bangumi信息
        if (enableBangumiIntegration) {
          _fetchBangumiInfoForResults();
        }
      }
    } catch (e) {
      final errorMessage = e.toString();
      if (errorMessage.contains('验证码') || errorMessage.contains('人机验证')) {
        error = '该网站需要验证码验证，暂时无法搜索';
      } else if (errorMessage.contains('SSL握手失败')) {
        error = 'SSL连接失败，网络不稳定或网站证书问题';
      } else if (errorMessage.contains('DNS解析失败')) {
        error = 'DNS解析失败，网站可能已失效';
      } else if (errorMessage.contains('403')) {
        error = '访问被拒绝，可能触发了反爬虫机制';
      } else if (errorMessage.contains('规则配置错误')) {
        error = '规则配置有误，请尝试其他规则源';
      } else {
        error = 'Search failed: $e';
      }
      Logger.error(error!);
    } finally {
      isLoading = false;
    }
  }

  /// 异步获取搜索结果的Bangumi信息
  @action
  Future<void> _fetchBangumiInfoForResults() async {
    if (!enableBangumiIntegration || searchResults.isEmpty) return;

    isFetchingBangumi = true;
    
    try {
      Logger.info('开始获取 ${searchResults.length} 个动漫的Bangumi信息');
      
      // 为每个搜索结果获取Bangumi信息
      for (int i = 0; i < searchResults.length; i++) {
        final item = searchResults[i];
        
        // 跳过已经搜索过的项目
        if (item.bangumiSearched) continue;
        
        try {
          final bangumiInfo = await _bangumiService.matchAnimeWithBangumi(item.title);
          
          // 更新搜索结果
          searchResults[i] = item.copyWithBangumi(bangumiInfo, searched: true);
          
          Logger.info('Bangumi匹配完成: ${item.title} -> ${bangumiInfo?.displayName ?? "未找到"}');
          
          // 添加小延迟避免请求过于频繁
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          Logger.error('获取Bangumi信息失败: ${item.title} - $e');
          // 标记为已搜索，避免重复尝试
          searchResults[i] = item.copyWithBangumi(null, searched: true);
        }
      }
      
      Logger.info('Bangumi信息获取完成');
    } catch (e) {
      Logger.error('批量获取Bangumi信息失败: $e');
    } finally {
      isFetchingBangumi = false;
    }
  }

  /// 手动刷新单个项目的Bangumi信息
  @action
  Future<void> refreshBangumiInfo(int index) async {
    if (!enableBangumiIntegration || index >= searchResults.length) return;

    final item = searchResults[index];
    
    try {
      isFetchingBangumi = true;
      
      final bangumiInfo = await _bangumiService.matchAnimeWithBangumi(item.title);
      searchResults[index] = item.copyWithBangumi(bangumiInfo, searched: true);
      
      Logger.info('刷新Bangumi信息完成: ${item.title}');
    } catch (e) {
      Logger.error('刷新Bangumi信息失败: $e');
    } finally {
      isFetchingBangumi = false;
    }
  }

  /// 切换Bangumi集成开关
  @action
  void toggleBangumiIntegration() {
    enableBangumiIntegration = !enableBangumiIntegration;
    Logger.info('Bangumi集成已${enableBangumiIntegration ? "启用" : "禁用"}');
  }

  /// 获取动漫详情
  @action
  Future<void> getAnimeDetail(AnimeItem item) async {
    if (selectedRule == null) return;

    try {
      isLoading = true;
      error = null;

      Logger.info('Getting anime detail: ${item.title}');

      final detail = await _animeService.getAnimeDetail(selectedRule!, item.detailUrl);
      if (detail != null) {
        currentAnimeDetail = detail;
        Logger.info('Got anime detail: ${detail.title} with ${detail.episodes.length} episodes');
      } else {
        error = 'Failed to get anime detail';
      }
    } catch (e) {
      error = 'Failed to get anime detail: $e';
      Logger.error(error!);
    } finally {
      isLoading = false;
    }
  }

  /// 播放动漫
  @action
  Future<void> playAnime(AnimeEpisode episode) async {
    if (selectedRule == null) return;

    try {
      Logger.info('Playing anime episode: ${episode.title}');

      final playUrl = await _animeService.getPlayUrl(selectedRule!, episode.episodeUrl);
      if (playUrl != null) {
        // TODO: 实现播放器逻辑
        Logger.info('Play URL: $playUrl');
      } else {
        error = 'Failed to get play URL';
      }
    } catch (e) {
      error = 'Failed to play anime: $e';
      Logger.error(error!);
    }
  }

  /// 清空搜索结果
  @action
  void clearSearchResults() {
    searchResults.clear();
    currentAnimeDetail = null;
    error = null;
  }

  /// 返回到搜索结果（只清空详情，保持搜索结果）
  @action
  void backToSearchResults() {
    currentAnimeDetail = null;
  }

  /// 添加动漫到收藏
  @action
  Future<bool> addToFavorites(AnimeDetail detail) async {
    try {
      final favorite = UnifiedFavorite.fromAnime(
        id: detail.detailUrl, // 使用详情URL作为ID
        source: detail.ruleKey,
        title: detail.title,
        cover: detail.coverUrl,
        episodeCount: detail.episodes.length,
        status: null,
      );

      final success = await _favoriteService.addFavorite(favorite);
      if (success) {
        Logger.info('添加动漫到收藏: ${detail.title}');
      }
      return success;
    } catch (e) {
      Logger.error('添加动漫收藏失败: $e');
      return false;
    }
  }

  /// 从 AnimeItem 添加到收藏（保留更多信息）
  @action
  Future<bool> addToFavoritesFromItem(AnimeItem item) async {
    try {
      final favorite = UnifiedFavorite.fromAnime(
        id: item.detailUrl,
        source: item.ruleKey,
        title: item.displayTitle, // 使用显示标题（可能包含Bangumi信息）
        cover: item.bestCoverUrl, // 使用最佳封面
        episodeCount: null,
        status: null,
      );

      final success = await _favoriteService.addFavorite(favorite);
      if (success) {
        Logger.info('添加动漫到收藏: ${item.displayTitle}');
      }
      return success;
    } catch (e) {
      Logger.error('添加动漫收藏失败: $e');
      return false;
    }
  }

  /// 从收藏中移除动漫
  @action
  Future<bool> removeFromFavorites(AnimeDetail detail) async {
    try {
      final success = await _favoriteService.removeFavorite(
        'anime',
        detail.ruleKey,
        detail.detailUrl,
      );
      if (success) {
        Logger.info('从收藏中移除动漫: ${detail.title}');
      }
      return success;
    } catch (e) {
      Logger.error('移除动漫收藏失败: $e');
      return false;
    }
  }

  /// 从 AnimeItem 移除收藏
  @action
  Future<bool> removeFromFavoritesFromItem(AnimeItem item) async {
    try {
      final success = await _favoriteService.removeFavorite(
        'anime',
        item.ruleKey,
        item.detailUrl,
      );
      if (success) {
        Logger.info('从收藏中移除动漫: ${item.title}');
      }
      return success;
    } catch (e) {
      Logger.error('移除动漫收藏失败: $e');
      return false;
    }
  }

  /// 切换收藏状态
  @action
  Future<bool> toggleFavorite(AnimeDetail detail) async {
    final isFav = await isFavorited(detail);
    if (isFav) {
      await removeFromFavorites(detail);
      return false;
    } else {
      await addToFavorites(detail);
      return true;
    }
  }

  /// 切换收藏状态（基于 AnimeItem）
  @action
  Future<bool> toggleFavoriteFromItem(AnimeItem item) async {
    final isFav = await isFavoritedFromItem(item);
    if (isFav) {
      await removeFromFavoritesFromItem(item);
      return false;
    } else {
      await addToFavoritesFromItem(item);
      return true;
    }
  }

  /// 检查是否已收藏
  Future<bool> isFavorited(AnimeDetail detail) async {
    return await _favoriteService.isFavorite(
      'anime',
      detail.ruleKey,
      detail.detailUrl,
    );
  }

  /// 检查是否已收藏（基于 AnimeItem）
  Future<bool> isFavoritedFromItem(AnimeItem item) async {
    return await _favoriteService.isFavorite(
      'anime',
      item.ruleKey,
      item.detailUrl,
    );
  }
}