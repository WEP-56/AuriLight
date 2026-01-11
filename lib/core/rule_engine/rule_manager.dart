import 'dart:io';
import 'package:hive/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/unified_rule.dart';
import '../utils/logger.dart';
import '../storage/storage.dart';
import 'rule_parser.dart';

part 'rule_manager.g.dart';

/// 统一规则管理器
class RuleManager extends _RuleManagerBase with _$RuleManager {
  static RuleManager? _instance;
  
  RuleManager._internal() : super._internal();
  
  factory RuleManager() {
    _instance ??= RuleManager._internal();
    return _instance!;
  }
}

abstract class _RuleManagerBase with Store {
  _RuleManagerBase._internal();

  late Box<UnifiedRule> _rulesBox;
  late String _rulesDirectory;
  final RuleParser _parser = RuleParser();

  @observable
  ObservableList<UnifiedRule> rules = ObservableList<UnifiedRule>();

  @observable
  bool isLoading = false;

  @observable
  String? error;

  /// 初始化规则管理器
  @action
  Future<void> initialize() async {
    try {
      isLoading = true;
      error = null;

      // 尝试打开Hive box，如果失败则清理数据
      try {
        _rulesBox = await Hive.openBox<UnifiedRule>('unified_rules');
      } catch (e) {
        Logger.warning('Failed to open rules box, clearing data: $e');
        await AppStorage.clearRulesData();
        _rulesBox = await Hive.openBox<UnifiedRule>('unified_rules');
      }

      // 设置规则目录
      final appDir = await getApplicationSupportDirectory();
      _rulesDirectory = path.join(appDir.path, 'rules');
      
      // 确保规则目录存在
      await _ensureRulesDirectory();

      // 初始化解析器
      await _parser.initCompiler();

      // 加载规则
      await loadRules();

      Logger.info('RuleManager initialized with ${rules.length} rules');
    } catch (e) {
      error = 'Failed to initialize rule manager: $e';
      Logger.error(error!);
    } finally {
      isLoading = false;
    }
  }

  /// 确保规则目录结构存在
  Future<void> _ensureRulesDirectory() async {
    final rulesDir = Directory(_rulesDirectory);
    final animeDir = Directory(path.join(_rulesDirectory, 'anime'));
    final mangaDir = Directory(path.join(_rulesDirectory, 'manga'));

    if (!await rulesDir.exists()) {
      await rulesDir.create(recursive: true);
    }
    if (!await animeDir.exists()) {
      await animeDir.create(recursive: true);
    }
    if (!await mangaDir.exists()) {
      await mangaDir.create(recursive: true);
    }

    Logger.info('Rules directory structure created at: $_rulesDirectory');
  }

  /// 加载所有规则
  @action
  Future<void> loadRules() async {
    try {
      isLoading = true;
      error = null;

      // 从文件系统扫描并解析规则
      final parsedRules = await _parser.scanAndParseRules(_rulesDirectory);
      
      // 更新数据库中的规则
      await _updateRulesInDatabase(parsedRules);

      // 从数据库加载规则并按排序顺序排列
      final allRules = _rulesBox.values.toList();
      allRules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      
      rules.clear();
      rules.addAll(allRules);

      Logger.info('Loaded ${rules.length} rules');
    } catch (e) {
      error = 'Failed to load rules: $e';
      Logger.error(error!);
    } finally {
      isLoading = false;
    }
  }

  /// 更新数据库中的规则
  Future<void> _updateRulesInDatabase(List<UnifiedRule> parsedRules) async {
    final Map<String, UnifiedRule> existingRules = {};
    for (final rule in _rulesBox.values) {
      existingRules[rule.key] = rule;
    }

    for (final parsedRule in parsedRules) {
      final existing = existingRules[parsedRule.key];
      if (existing != null) {
        // 更新现有规则，保留用户设置
        existing.name = parsedRule.name;
        existing.version = parsedRule.version;
        existing.baseUrl = parsedRule.baseUrl;
        existing.rawData = parsedRule.rawData;
        existing.searchConfig = parsedRule.searchConfig;
        existing.detailConfig = parsedRule.detailConfig;
        existing.playConfig = parsedRule.playConfig;
        existing.accountConfig = parsedRule.accountConfig;
        existing.updatedAt = DateTime.now();
        await existing.save();
      } else {
        // 添加新规则
        await _rulesBox.put(parsedRule.key, parsedRule);
      }
    }

    // 移除不存在的规则文件对应的规则
    final parsedKeys = parsedRules.map((r) => r.key).toSet();
    final toRemove = <String>[];
    for (final key in existingRules.keys) {
      if (!parsedKeys.contains(key)) {
        final rule = existingRules[key]!;
        if (!await File(rule.filePath).exists()) {
          toRemove.add(key);
        }
      }
    }
    for (final key in toRemove) {
      await _rulesBox.delete(key);
      Logger.info('Removed obsolete rule: $key');
    }
  }

  /// 获取启用的规则
  @computed
  List<UnifiedRule> get enabledRules => rules.where((r) => r.enabled).toList();

  /// 获取动漫规则
  @computed
  List<UnifiedRule> get animeRules => 
      rules.where((r) => r.type == RuleType.anime).toList();

  /// 获取漫画规则
  @computed
  List<UnifiedRule> get mangaRules => 
      rules.where((r) => r.type == RuleType.manga).toList();

  /// 获取启用的动漫规则
  @computed
  List<UnifiedRule> get enabledAnimeRules => 
      animeRules.where((r) => r.enabled).toList();

  /// 获取启用的漫画规则
  @computed
  List<UnifiedRule> get enabledMangaRules => 
      mangaRules.where((r) => r.enabled).toList();

  /// 根据key获取规则
  UnifiedRule? getRuleByKey(String key) {
    try {
      return rules.firstWhere((r) => r.key == key);
    } catch (e) {
      return null;
    }
  }

  /// 切换规则启用状态
  @action
  Future<void> toggleRuleEnabled(String key) async {
    final rule = getRuleByKey(key);
    if (rule != null) {
      rule.toggleEnabled();
      Logger.info('Toggled rule ${rule.name}: ${rule.enabled}');
    }
  }

  /// 更新规则排序
  @action
  Future<void> updateRuleOrder(List<String> orderedKeys) async {
    for (int i = 0; i < orderedKeys.length; i++) {
      final rule = getRuleByKey(orderedKeys[i]);
      if (rule != null) {
        rule.updateSortOrder(i);
      }
    }
    
    // 重新排序本地列表
    rules.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    
    Logger.info('Updated rule order');
  }

  /// 添加规则文件
  @action
  Future<bool> addRuleFile(String filePath) async {
    try {
      isLoading = true;
      error = null;

      // 验证文件格式
      if (!await _parser.validateRuleFile(filePath)) {
        error = 'Invalid rule file format';
        return false;
      }

      // 解析规则以确定目标目录（避免把 manga JSON 误判为 anime）
      final parsedRule = await _parser.reparseRule(filePath);
      if (parsedRule == null) {
        error = 'Failed to parse rule file';
        return false;
      }

      final fileName = path.basename(filePath);
      final targetDir = parsedRule.type == RuleType.manga ? 'manga' : 'anime';
      final targetPath = path.join(_rulesDirectory, targetDir, fileName);

      // 复制文件
      final sourceFile = File(filePath);
      final targetFile = File(targetPath);
      await sourceFile.copy(targetPath);

      // 解析并添加规则
      final rule = await _parser.reparseRule(targetPath);
      if (rule != null) {
        await _rulesBox.put(rule.key, rule);
        rules.add(rule);
        Logger.info('Added rule: ${rule.name}');
        return true;
      } else {

        // 删除复制的文件
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        error = 'Failed to parse rule file';
        return false;
      }
    } catch (e) {
      error = 'Failed to add rule file: $e';
      Logger.error(error!);
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// 删除规则
  @action
  Future<bool> removeRule(String key) async {
    try {
      final rule = getRuleByKey(key);
      if (rule == null) return false;

      // 删除文件
      final file = File(rule.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 从数据库删除
      await _rulesBox.delete(key);
      
      // 从列表删除
      rules.removeWhere((r) => r.key == key);

      Logger.info('Removed rule: ${rule.name}');
      return true;
    } catch (e) {
      error = 'Failed to remove rule: $e';
      Logger.error(error!);
      return false;
    }
  }

  /// 刷新规则
  @action
  Future<void> refreshRules() async {
    await loadRules();
  }

  /// 强制重置规则数据库（调试用）
  @action
  Future<void> resetRulesDatabase() async {
    try {
      isLoading = true;
      error = null;
      
      // 清空当前规则
      rules.clear();
      
      // 清理数据库
      await _rulesBox.clear();
      
      // 重新加载规则
      await loadRules();
      
      Logger.info('Rules database reset successfully');
    } catch (e) {
      error = 'Failed to reset rules database: $e';
      Logger.error(error!);
    } finally {
      isLoading = false;
    }
  }

  /// 获取规则目录路径
  String get rulesDirectory => _rulesDirectory;

  /// 获取动漫规则目录路径
  String get animeRulesDirectory => path.join(_rulesDirectory, 'anime');

  /// 获取漫画规则目录路径
  String get mangaRulesDirectory => path.join(_rulesDirectory, 'manga');

  /// 释放资源
  void dispose() {
    _parser.dispose();
  }
}