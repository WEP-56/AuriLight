import 'package:mobx/mobx.dart';
import 'package:hive/hive.dart';

import '../../core/models/manga_item.dart';
import '../../core/models/unified_models.dart';
import '../../core/services/manga_auth_service.dart';
import '../../core/services/manga_rule_manager.dart';
import '../../core/services/favorite_service.dart';
import '../../core/utils/logger.dart';

part 'manga_store.g.dart';

abstract class _MangaStore with Store {
  final MangaRuleManager _ruleManager = MangaRuleManager();
  final MangaAuthService _auth = MangaAuthService();
  final FavoriteService _favoriteService = FavoriteService();
  
  // Hive boxes
  Box<UnifiedHistory>? _historyBox;

  @observable
  ObservableList<MangaRuleInfo> availableRules = ObservableList<MangaRuleInfo>();

  @observable
  ObservableList<String> loadedRules = ObservableList<String>();

  @observable
  String? selectedRuleKey;

  @observable
  bool selectedRuleHasAccount = false;

  @observable
  bool isLoggedIn = false;

  @observable
  ObservableList<MangaItem> searchResults = ObservableList<MangaItem>();

  @observable
  bool isSearching = false;

  @observable
  String searchKeyword = '';

  @observable
  int currentPage = 1;

  @observable
  bool hasMorePages = true;

  @observable
  MangaDetail? currentDetail;

  @observable
  bool isLoadingDetail = false;

  @observable
  ObservableList<String> currentChapterImages = ObservableList<String>();

  @observable
  String? currentChapterId; // 当前章节ID，用于JM图片解密

  @observable
  bool isLoadingChapter = false;

  @observable
  ObservableList<UnifiedFavorite> favorites = ObservableList<UnifiedFavorite>();

  @observable
  ObservableList<UnifiedHistory> history = ObservableList<UnifiedHistory>();

  @observable
  String currentView = 'search'; // 'search', 'detail', 'reader'

  /// 初始化
  @action
  Future<void> initialize() async {
    try {
      Logger.info('初始化漫画模块...');
      
      // 初始化Hive boxes
      await _initializeHive();
      
      // 扫描可用规则
      await _ruleManager.scanAssetRules();
      await _loadAvailableRules();
      
      // 加载收藏和历史
      await _loadFavorites();
      await _loadHistory();
      
      // 刷新登录状态（从持久化 token 判定）
      await _refreshLoginState(null);
      
      Logger.info('漫画模块初始化完成');
    } catch (e) {
      Logger.error('漫画模块初始化失败: $e');
    }
  }

  /// 初始化Hive存储
  Future<void> _initializeHive() async {
    try {
      _historyBox = await Hive.openBox<UnifiedHistory>('unified_history');
    } catch (e) {
      Logger.error('Hive初始化失败: $e');
    }
  }

  /// 加载可用规则
  @action
  Future<void> _loadAvailableRules() async {
    final rules = _ruleManager.availableRules.values.toList();
    availableRules.clear();
    availableRules.addAll(rules);
    
    final loaded = _ruleManager.loadedRules.toList();
    loadedRules.clear();
    loadedRules.addAll(loaded);
  }

  /// 选择规则源
  @action
  void selectRule(String ruleKey) {
    selectedRuleKey = ruleKey;
    selectedRuleHasAccount = false;
    // 清空搜索结果
    searchResults.clear();
    currentPage = 1;
    hasMorePages = true;

    // 预加载规则，以便在搜索页就能判断是否支持登录
    _preloadSelectedRule(ruleKey);
  }

  Future<void> _preloadSelectedRule(String ruleKey) async {
    try {
      await _ruleManager.loadRule(ruleKey);
    } catch (e) {
      Logger.error('预加载规则失败: $e');
    } finally {
      // 刷新 loadedRules / hasAccount 状态
      final loaded = _ruleManager.loadedRules.toList();
      loadedRules
        ..clear()
        ..addAll(loaded);

      selectedRuleHasAccount = _ruleManager.supportsAccount(ruleKey);

      // 刷新登录状态（从持久化 token 判定）
      await _refreshLoginState(ruleKey);
    }
  }

  Future<void> _refreshLoginState(String? ruleKey) async {
    if (ruleKey == null) {
      isLoggedIn = false;
      return;
    }
    try {
      await _auth.ensureInitialized();
      isLoggedIn = _auth.getToken(ruleKey) != null;
    } catch (e) {
      Logger.warning('刷新登录状态失败: $e');
      isLoggedIn = false;
    }
  }

  /// 搜索漫画
  @action
  Future<void> search(String keyword, {bool loadMore = false}) async {
    print('[MangaStore] search方法被调用: $keyword');
    print('[MangaStore] selectedRuleKey: $selectedRuleKey');
    Logger.info('搜索被调用: keyword=$keyword, selectedRuleKey=$selectedRuleKey');
    
    if (selectedRuleKey == null) {
      print('[MangaStore] selectedRuleKey为null，返回');
      Logger.warning('未选择规则源');
      return;
    }

    print('[MangaStore] 开始搜索逻辑');
    try {
      isSearching = true;
      print('[MangaStore] 设置isSearching=true');
      
      if (!loadMore) {
        searchKeyword = keyword;
        currentPage = 1;
        searchResults.clear();
        print('[MangaStore] 清空搜索结果，重置页码');
      } else {
        currentPage++;
        print('[MangaStore] 加载更多，页码: $currentPage');
      }

      Logger.info('搜索漫画: $keyword, 页码: $currentPage, 规则: $selectedRuleKey');
      print('[MangaStore] 调用规则管理器搜索');
      
      final results = await _ruleManager.search(selectedRuleKey!, keyword, currentPage);
      Logger.info('规则管理器返回结果: ${results.length} 个');
      print('[MangaStore] 规则管理器返回: ${results.length} 个结果');
      
      if (results.isNotEmpty) {
        searchResults.addAll(results);
        Logger.info('搜索完成，获得 ${results.length} 个结果');
        print('[MangaStore] 添加到搜索结果');
      } else {
        hasMorePages = false;
        Logger.info('没有更多结果');
        print('[MangaStore] 没有更多结果');
      }
    } catch (e) {
      Logger.error('搜索失败: $e');
      print('[MangaStore] 搜索异常: $e');
    } finally {
      isSearching = false;
      print('[MangaStore] 设置isSearching=false');
    }
  }

  /// 获取漫画详情
  @action
  Future<void> loadDetail(String ruleKey, String comicId) async {
    try {
      isLoadingDetail = true;
      currentDetail = null;
      currentView = 'detail';
      
      Logger.info('加载漫画详情: $comicId');
      
      final detail = await _ruleManager.getDetail(ruleKey, comicId);
      
      if (detail != null) {
        currentDetail = detail;
        
        // 添加到历史记录
        await _addToHistory(detail);
        
        Logger.info('详情加载完成: ${detail.title}');
      } else {
        Logger.warning('详情加载失败: $comicId');
      }
    } catch (e) {
      Logger.error('加载详情异常: $e');
    } finally {
      isLoadingDetail = false;
    }
  }

  /// 获取章节内容
  @action
  Future<void> loadChapter(String ruleKey, String comicId, String chapterId) async {
    try {
      isLoadingChapter = true;
      currentChapterImages.clear();
      currentChapterId = chapterId; // 保存章节ID用于JM解密
      
      Logger.info('加载章节内容: $chapterId');
      
      final images = await _ruleManager.getChapter(ruleKey, comicId, chapterId);
      
      if (images.isNotEmpty) {
        currentChapterImages.addAll(images);
        currentView = 'reader';
        Logger.info('章节加载完成，共 ${images.length} 页');
      } else {
        Logger.warning('章节加载失败: $chapterId');
      }
    } catch (e) {
      Logger.error('加载章节异常: $e');
    } finally {
      isLoadingChapter = false;
    }
  }

  /// 添加到收藏
  @action
  Future<void> addToFavorites(MangaItem item) async {
    try {
      final favorite = UnifiedFavorite.fromManga(
        id: item.id,
        source: item.ruleKey,
        title: item.title,
        cover: item.cover,
        author: null,
        tags: item.tags,
      );

      await _favoriteService.addFavorite(favorite);
      await _loadFavorites();
      
      Logger.info('添加到收藏: ${item.title}');
    } catch (e) {
      Logger.error('添加收藏失败: $e');
    }
  }

  /// 添加详情到收藏
  @action
  Future<void> addDetailToFavorites(MangaDetail detail) async {
    try {
      // 提取所有标签
      List<String>? allTags;
      if (detail.tags != null) {
        allTags = [];
        detail.tags!.forEach((_, tagList) {
          allTags!.addAll(tagList);
        });
      }

      final favorite = UnifiedFavorite.fromManga(
        id: detail.id,
        source: detail.ruleKey,
        title: detail.title,
        cover: detail.cover,
        chapterCount: detail.chapters?.length,
        author: detail.uploader,
        tags: allTags,
      );

      await _favoriteService.addFavorite(favorite);
      await _loadFavorites();
      
      Logger.info('添加到收藏: ${detail.title}');
    } catch (e) {
      Logger.error('添加收藏失败: $e');
    }
  }

  /// 从收藏中移除
  @action
  Future<void> removeFromFavorites(String ruleKey, String itemId) async {
    try {
      await _favoriteService.removeFavorite('manga', ruleKey, itemId);
      await _loadFavorites();
      
      Logger.info('从收藏中移除: $itemId');
    } catch (e) {
      Logger.error('移除收藏失败: $e');
    }
  }

  /// 切换收藏状态
  @action
  Future<bool> toggleFavorite(MangaDetail detail) async {
    try {
      final isFav = await _favoriteService.isFavorite('manga', detail.ruleKey, detail.id);
      
      if (isFav) {
        await removeFromFavorites(detail.ruleKey, detail.id);
        return false;
      } else {
        await addDetailToFavorites(detail);
        return true;
      }
    } catch (e) {
      Logger.error('切换收藏状态失败: $e');
      return false;
    }
  }

  /// 检查是否已收藏
  Future<bool> isFavorited(String ruleKey, String itemId) async {
    return await _favoriteService.isFavorite('manga', ruleKey, itemId);
  }

  /// 同步检查是否已收藏（用于UI）
  bool isFavoritedSync(String ruleKey, String itemId) {
    // 从缓存的收藏列表中检查
    return favorites.any((f) => f.source == ruleKey && f.id == itemId);
  }

  /// 添加到历史记录
  Future<void> _addToHistory(MangaDetail detail) async {
    try {
      final history = UnifiedHistory.fromManga(
        mangaId: detail.id,
        source: detail.ruleKey,
        title: detail.title,
        cover: detail.cover,
        chapter: '详情页',
      );

      await _historyBox?.put('manga_${detail.ruleKey}_${detail.id}', history);
      await _loadHistory();
    } catch (e) {
      Logger.error('添加历史记录失败: $e');
    }
  }

  /// 更新阅读进度
  @action
  Future<void> updateReadingProgress(String ruleKey, String mangaId, String chapter, int page) async {
    try {
      final key = 'manga_${ruleKey}_$mangaId';
      final existingHistory = _historyBox?.get(key);
      
      if (existingHistory != null) {
        final updatedHistory = existingHistory.updateProgress({
          'chapter': chapter,
          'page': page,
        });
        await _historyBox?.put(key, updatedHistory);
      }
      
      await _loadHistory();
    } catch (e) {
      Logger.error('更新阅读进度失败: $e');
    }
  }

  /// 加载收藏列表
  @action
  Future<void> _loadFavorites() async {
    try {
      final mangaFavorites = await _favoriteService.getMangaFavorites();
      favorites.clear();
      favorites.addAll(mangaFavorites);
    } catch (e) {
      Logger.error('加载收藏列表失败: $e');
    }
  }

  /// 加载历史记录
  @action
  Future<void> _loadHistory() async {
    try {
      final allHistory = _historyBox?.values.where((h) => h.isManga).toList() ?? [];
      // 按最后访问时间排序
      allHistory.sort((a, b) => b.lastAccess.compareTo(a.lastAccess));
      
      history.clear();
      history.addAll(allHistory);
    } catch (e) {
      Logger.error('加载历史记录失败: $e');
    }
  }

  /// 用户登录
  @action
  Future<bool> login(String ruleKey, String username, String password) async {
    try {
      Logger.info('尝试登录: $ruleKey');
      final ok = await _ruleManager.login(ruleKey, username, password);
      await _refreshLoginState(ruleKey);
      return ok;
    } catch (e) {
      Logger.error('登录失败: $e');
      await _refreshLoginState(ruleKey);
      return false;
    }
  }

  bool supportsAccountForRule(String? ruleKey) {
    if (ruleKey == null) return false;
    if (ruleKey == selectedRuleKey) {
      return selectedRuleHasAccount;
    }
    return _ruleManager.supportsAccount(ruleKey);
  }

  @action
  Future<bool> reLogin(String ruleKey) async {
    try {
      Logger.info('尝试重登: $ruleKey');
      final ok = await _ruleManager.reLogin(ruleKey);
      await _refreshLoginState(ruleKey);
      return ok;
    } catch (e) {
      Logger.error('重登失败: $e');
      await _refreshLoginState(ruleKey);
      return false;
    }
  }

  @action
  Future<void> logout(String ruleKey) async {
    try {
      Logger.info('尝试退出登录: $ruleKey');
      await _ruleManager.logout(ruleKey);
      await _refreshLoginState(ruleKey);
    } catch (e) {
      Logger.error('退出登录失败: $e');
      await _refreshLoginState(ruleKey);
    }
  }

  /// 返回搜索页面
  @action
  void backToSearch() {
    currentView = 'search';
    currentDetail = null;
    currentChapterImages.clear();
    currentChapterId = null;
  }

  /// 返回详情页面
  @action
  void backToDetail() {
    currentView = 'detail';
    currentChapterImages.clear();
    currentChapterId = null;
  }

  /// 获取当前规则的 CDN 回退配置
  List<String>? getCdnFallbacksForCurrentRule() {
    final key = selectedRuleKey;
    if (key == null) return null;
    return _ruleManager.getReaderCdnFallbacks(key);
  }
  
  /// 获取指定规则的基础URL
  String? getBaseUrlForRule(String? ruleKey) {
    if (ruleKey == null) return null;
    return _ruleManager.getBaseUrl(ruleKey);
  }

  /// 获取阅读器 Referer（若规则未定义则返回 baseUrl）
  String? getReaderRefererForRule(String? ruleKey) {
    if (ruleKey == null) return null;
    return _ruleManager.getReaderReferer(ruleKey);
  }

  /// 获取阅读器 headers
  Map<String, String>? getReaderHeadersForRule(String? ruleKey) {
    if (ruleKey == null) return null;
    return _ruleManager.getReaderHeaders(ruleKey);
  }

  /// 获取阅读器是否使用 WebView
  bool getUseWebviewForRule(String? ruleKey) {
    if (ruleKey == null) return false;
    return _ruleManager.getUseWebview(ruleKey);
  }

  /// 清理资源
  void dispose() {
    _ruleManager.clearAll();
  }
}

class MangaStore = _MangaStore with _$MangaStore;