import 'package:mobx/mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../core/rule_engine/rule_manager.dart';
import '../../core/models/unified_rule.dart';
import '../anime/anime_store.dart';

part 'home_store.g.dart';

/// 主页状态管理
class HomeStore = _HomeStoreBase with _$HomeStore;

abstract class _HomeStoreBase with Store {
  final RuleManager _ruleManager = Modular.get<RuleManager>();
  final AnimeStore _animeStore = Modular.get<AnimeStore>();

  @observable
  String currentRoute = '/';

  /// 设置当前路由
  @action
  void setCurrentRoute(String route) {
    currentRoute = route;
  }

  @observable
  bool isInitialized = false;

  @observable
  String? error;

  /// 初始化
  @action
  Future<void> initialize() async {
    try {
      await _ruleManager.initialize();
      isInitialized = true;
    } catch (e) {
      error = 'Failed to initialize: $e';
    }
  }

  /// 获取启用的规则列表（用于侧边栏）
  @computed
  List<UnifiedRule> get enabledRules => _ruleManager.enabledRules;

  /// 获取动漫规则数量
  @computed
  int get animeRulesCount => _ruleManager.enabledAnimeRules.length;

  /// 获取漫画规则数量
  @computed
  int get mangaRulesCount => _ruleManager.enabledMangaRules.length;

  /// 选择侧边栏项目
  @action
  void selectItem(int index) {
    switch (index) {
      case 0:
        setCurrentRoute('/');
        break;
      case 1:
        setCurrentRoute('/favorites');
        break;
      case 2:
        setCurrentRoute('/downloads');
        break;
      case 3:
        setCurrentRoute('/history');
        break;
      case 4:
        setCurrentRoute('/settings');
        break;
    }
  }

  /// 导航到动漫页面
  @action
  void navigateToAnime(String ruleKey) {
    setCurrentRoute('/anime/$ruleKey');
  }

  /// 获取当前选中的索引
  @computed
  int get selectedIndex {
    if (currentRoute == '/') return 0;
    if (currentRoute == '/favorites') return 1;
    if (currentRoute == '/downloads') return 2;
    if (currentRoute == '/history') return 3;
    if (currentRoute == '/settings') return 4;
    return -1; // 动漫页面等其他页面
  }

  /// 检查是否正在搜索（禁用某些操作）
  @computed
  bool get isSearching => _animeStore.isLoading;

  /// 切换规则启用状态
  @action
  Future<void> toggleRuleEnabled(String key) async {
    if (isSearching) return; // 搜索期间禁用操作
    await _ruleManager.toggleRuleEnabled(key);
  }

  /// 更新规则排序
  @action
  Future<void> updateRuleOrder(List<String> orderedKeys) async {
    if (isSearching) return; // 搜索期间禁用操作
    await _ruleManager.updateRuleOrder(orderedKeys);
  }

  /// 刷新规则
  @action
  Future<void> refreshRules() async {
    if (isSearching) return; // 搜索期间禁用操作
    await _ruleManager.refreshRules();
  }

  /// 从文件导入规则
  @action
  Future<bool> importRuleFromFile(String filePath) async {
    if (isSearching) return false; // 搜索期间禁用操作
    try {
      final success = await _ruleManager.addRuleFile(filePath);
      if (success) {
        // 导入成功后刷新规则列表
        await refreshRules();
      }
      return success;
    } catch (e) {
      error = 'Failed to import rule: $e';
      return false;
    }
  }

  /// 删除规则
  @action
  Future<void> deleteRule(String key) async {
    if (isSearching) return; // 搜索期间禁用操作
    try {
      await _ruleManager.removeRule(key);
      // 删除成功后刷新规则列表
      await refreshRules();
    } catch (e) {
      error = 'Failed to delete rule: $e';
    }
  }

  /// 重置规则数据库（调试用）
  @action
  Future<void> resetRulesDatabase() async {
    if (isSearching) return; // 搜索期间禁用操作
    try {
      await _ruleManager.resetRulesDatabase();
    } catch (e) {
      error = 'Failed to reset rules database: $e';
    }
  }
}