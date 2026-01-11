import 'package:flutter/services.dart';
import '../utils/logger.dart';
import '../models/manga_item.dart';
import 'manga_js_engine.dart';
import 'manga_json_engine.dart';
import 'dart:convert';

/// 漫画规则信息
class MangaRuleInfo {
  final String key;
  final String name;
  final String version;
  final String? description;
  final String? url;
  final String? author;
  final List<String>? tags;
  final String filePath;
  final String type; // 'js' 或 'json'

  MangaRuleInfo({
    required this.key,
    required this.name,
    required this.version,
    this.description,
    this.url,
    this.author,
    this.tags,
    required this.filePath,
    required this.type,
  });

  /// 从JS规则内容解析规则信息
  factory MangaRuleInfo.fromJsContent(String content, String filePath) {
    try {
      // 简单的正则解析，提取基本信息
      final nameMatch = RegExp(r'name\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final keyMatch = RegExp(r'key\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final versionMatch = RegExp(r'version\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final urlMatch = RegExp(r'url\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      
      final name = nameMatch?.group(1) ?? '未知规则';
      final key = keyMatch?.group(1) ?? filePath.split('/').last.replaceAll('.js', '');
      final version = versionMatch?.group(1) ?? '1.0.0';
      final url = urlMatch?.group(1);

      return MangaRuleInfo(
        key: key,
        name: name,
        version: version,
        url: url,
        filePath: filePath,
        type: 'js',
      );
    } catch (e) {
      Logger.warning('解析规则信息失败: $filePath, 错误: $e');
      return MangaRuleInfo(
        key: filePath.split('/').last.replaceAll('.js', ''),
        name: '未知规则',
        version: '1.0.0',
        filePath: filePath,
        type: 'js',
      );
    }
  }

  /// 从JSON规则内容解析规则信息
  factory MangaRuleInfo.fromJsonContent(String content, String filePath) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      final name = json['displayName'] ?? json['name'] ?? '未知规则';
      final key = json['name'] ?? filePath.split('/').last.replaceAll('.json', '');
      final version = json['version'] ?? '1.0.0';
      final url = json['url'];

      return MangaRuleInfo(
        key: key,
        name: name,
        version: version,
        url: url,
        filePath: filePath,
        type: 'json',
      );
    } catch (e) {
      Logger.warning('解析JSON规则信息失败: $filePath, 错误: $e');
      return MangaRuleInfo(
        key: filePath.split('/').last.replaceAll('.json', ''),
        name: '未知规则',
        version: '1.0.0',
        filePath: filePath,
        type: 'json',
      );
    }
  }

  @override
  String toString() {
    return 'MangaRuleInfo(key: $key, name: $name, version: $version, type: $type)';
  }
}

/// 漫画规则管理器 - 扫描、加载和管理JS/JSON规则
class MangaRuleManager {
  static final MangaRuleManager _instance = MangaRuleManager._internal();
  factory MangaRuleManager() => _instance;
  MangaRuleManager._internal();

  final MangaJsEngine _jsEngine = MangaJsEngine();
  final Map<String, MangaJsonEngine> _jsonEngines = {};
  final Map<String, MangaRuleInfo> _availableRules = {};
  final Set<String> _loadedRules = {};

  /// 获取所有可用规则
  Map<String, MangaRuleInfo> get availableRules => Map.unmodifiable(_availableRules);

  /// 获取已加载规则
  Set<String> get loadedRules => Set.unmodifiable(_loadedRules);

  /// 扫描assets中的漫画规则
  Future<void> scanAssetRules() async {
    try {
      Logger.info('开始扫描漫画规则...');
      
      // 使用预定义的规则文件列表（与规则源抽屉保持一致）
      await _scanPredefinedRules();
      
      Logger.info('漫画规则扫描完成，发现 ${_availableRules.length} 个规则');
    } catch (e) {
      Logger.error('扫描漫画规则失败: $e');
    }
  }

  /// 扫描预定义的规则文件（仅JSON规则）
  Future<void> _scanPredefinedRules() async {
    // 预定义的规则文件列表（仅JSON）
    final predefinedRules = [
      'baihehui', 'baozi', 'ccc', 'comic_walker', 'comick', 'copy_manga',
      'ehentai', 'example_manga', 'goda', 'hcomic', 'hitomi', 'ikmmh',
      'jm', 'komga', 'komiic', 'lanraragi', 'manga_dex', 'manhuagui',
      'manhuaren', 'manwaba', 'mh1234', 'mh18', 'mxs', 'nhentai',
      'picacg', 'shonen_jump_plus', 'wnacg', 'ykmh', 'zaimanhua',
    ];

    Logger.info('扫描预定义JSON漫画规则，共 ${predefinedRules.length} 个');

    for (final ruleKey in predefinedRules) {
      // 只尝试JSON规则
      await _scanSingleRule('assets/rules/manga/${ruleKey}_converted.json');
      await _scanSingleRule('assets/rules/manga/$ruleKey.json');
    }
  }

  /// 扫描单个规则文件（仅扫描JSON规则）
  Future<void> _scanSingleRule(String assetPath) async {
    try {
      // 只扫描JSON文件
      if (!assetPath.endsWith('.json')) {
        return;
      }
      
      String content;
      
      // 如果是转换后的JSON文件，优先从文档目录读取
      if (assetPath.endsWith('_converted.json')) {
        content = await _readConvertedJsonRule(assetPath);
      } else {
        content = await rootBundle.loadString(assetPath);
      }
      
      final ruleInfo = MangaRuleInfo.fromJsonContent(content, assetPath);
      _availableRules[ruleInfo.key] = ruleInfo;
      Logger.debug('发现JSON漫画规则: ${ruleInfo.name} (${ruleInfo.key})');
    } catch (e) {
      // 文件不存在或解析失败，忽略
      Logger.debug('JSON规则文件不存在或解析失败: $assetPath');
    }
  }

  /// 读取转换后的JSON规则文件
  Future<String> _readConvertedJsonRule(String assetPath) async {
    // 直接从assets目录读取（转换后的文件已保存到项目assets目录）
    return await rootBundle.loadString(assetPath);
  }

  /// 加载指定规则（仅支持JSON规则）
  Future<bool> loadRule(String ruleKey) async {
    try {
      final ruleInfo = _availableRules[ruleKey];
      if (ruleInfo == null) {
        Logger.warning('规则不存在: $ruleKey');
        return false;
      }

      if (_loadedRules.contains(ruleKey)) {
        Logger.info('规则已加载: $ruleKey');
        return true;
      }

      // 只支持JSON规则
      if (ruleInfo.type != 'json') {
        Logger.warning('不支持的规则类型: ${ruleInfo.type}, 请使用JSON规则');
        return false;
      }

      Logger.info('加载JSON漫画规则: ${ruleInfo.name}');
      
      // 读取JSON规则内容
      String content;
      if (ruleInfo.filePath.endsWith('_converted.json')) {
        content = await _readConvertedJsonRule(ruleInfo.filePath);
      } else {
        content = await rootBundle.loadString(ruleInfo.filePath);
      }
      
      try {
        final jsonEngine = MangaJsonEngine(content);
        await jsonEngine.refreshDomains(); // 初始化域名
        _jsonEngines[ruleKey] = jsonEngine;
        _loadedRules.add(ruleKey);
        Logger.info('JSON规则加载成功: ${ruleInfo.name}');
        return true;
      } catch (e) {
        Logger.error('JSON规则加载失败: ${ruleInfo.name}, 错误: $e');
        return false;
      }
      
    } catch (e) {
      Logger.error('加载规则异常 [$ruleKey]: $e');
      return false;
    }
  }

  /// 卸载指定规则
  void unloadRule(String ruleKey) {
    if (_loadedRules.contains(ruleKey)) {
      final ruleInfo = _availableRules[ruleKey];
      if (ruleInfo?.type == 'json') {
        _jsonEngines.remove(ruleKey);
      } else {
        _jsEngine.clearRule(ruleKey);
      }
      _loadedRules.remove(ruleKey);
      Logger.info('规则已卸载: $ruleKey');
    }
  }

  /// 批量加载规则
  Future<List<String>> loadRules(List<String> ruleKeys) async {
    final loadedKeys = <String>[];
    
    for (final ruleKey in ruleKeys) {
      final success = await loadRule(ruleKey);
      if (success) {
        loadedKeys.add(ruleKey);
      }
    }
    
    Logger.info('批量加载完成: ${loadedKeys.length}/${ruleKeys.length}');
    return loadedKeys;
  }

  bool supportsAccount(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    return engine?.supportsAccount == true;
  }

  Future<bool> login(String ruleKey, String username, String password) async {
    if (!_loadedRules.contains(ruleKey)) {
      final loaded = await loadRule(ruleKey);
      if (!loaded) return false;
    }
    final engine = _jsonEngines[ruleKey];
    if (engine == null || engine.supportsAccount != true) return false;
    return await engine.login(username, password);
  }

  Future<bool> reLogin(String ruleKey) async {
    if (!_loadedRules.contains(ruleKey)) {
      final loaded = await loadRule(ruleKey);
      if (!loaded) return false;
    }
    final engine = _jsonEngines[ruleKey];
    if (engine == null || engine.supportsAccount != true) return false;
    return await engine.reLogin();
  }

  Future<void> logout(String ruleKey) async {
    if (!_loadedRules.contains(ruleKey)) {
      final loaded = await loadRule(ruleKey);
      if (!loaded) return;
    }
    final engine = _jsonEngines[ruleKey];
    if (engine == null || engine.supportsAccount != true) return;
    await engine.logout();
  }

  /// 搜索漫画（仅支持JSON规则）
  Future<List<MangaItem>> search(String ruleKey, String keyword, int page) async {
    Logger.info('搜索请求: ruleKey=$ruleKey, keyword=$keyword, page=$page');
    Logger.info('当前已加载规则: $_loadedRules');
    
    if (!_loadedRules.contains(ruleKey)) {
      Logger.info('规则未加载，开始加载: $ruleKey');
      final loaded = await loadRule(ruleKey);
      Logger.info('规则加载结果: $loaded');
      if (!loaded) {
        Logger.warning('规则加载失败，无法搜索: $ruleKey');
        return [];
      }
    } else {
      Logger.info('规则已加载');
    }

    final ruleInfo = _availableRules[ruleKey];
    Logger.info('规则信息: ${ruleInfo?.toString()}');
    
    // 只支持JSON规则
    if (ruleInfo?.type != 'json') {
      Logger.error('不支持的规则类型: ${ruleInfo?.type}');
      return [];
    }
    
    Logger.info('使用JSON引擎搜索');
    final jsonEngine = _jsonEngines[ruleKey];
    if (jsonEngine != null) {
      Logger.info('JSON引擎存在，开始搜索');
      try {
        final results = await jsonEngine.search(keyword, page: page);
        Logger.info('JSON引擎返回: ${results.length} 个结果');
        return results;
      } catch (e) {
        Logger.error('JSON引擎搜索失败: $e');
        return [];
      }
    } else {
      Logger.error('JSON引擎不存在');
      return [];
    }
  }

  /// 获取漫画详情（仅支持JSON规则）
  Future<MangaDetail?> getDetail(String ruleKey, String comicId) async {
    if (!_loadedRules.contains(ruleKey)) {
      final loaded = await loadRule(ruleKey);
      if (!loaded) {
        Logger.warning('规则加载失败，无法获取详情: $ruleKey');
        return null;
      }
    }

    final ruleInfo = _availableRules[ruleKey];
    if (ruleInfo?.type == 'json') {
      final jsonEngine = _jsonEngines[ruleKey];
      if (jsonEngine != null) {
        final detail = await jsonEngine.getDetail(comicId);
        if (detail == null) return null;
        // 统一使用 RuleManager 的规则名称与 key
        return MangaDetail(
          id: detail.id,
          title: detail.title,
          subtitle: detail.subtitle,
          cover: detail.cover,
          description: detail.description,
          tags: detail.tags,
          chapters: detail.chapters,
          thumbnails: detail.thumbnails,
          recommend: detail.recommend,
          commentCount: detail.commentCount,
          uploader: detail.uploader,
          updateTime: detail.updateTime,
          uploadTime: detail.uploadTime,
          url: detail.url,
          stars: detail.stars,
          isFavorite: detail.isFavorite,
          ruleName: _availableRules[ruleKey]?.name ?? detail.ruleName,
          ruleKey: ruleKey,
        );
      }
    } else {
      Logger.warning('不支持的规则类型: ${ruleInfo?.type}');
    }
    return null;
  }

  /// 获取章节内容（仅支持JSON规则）
  Future<List<String>> getChapter(String ruleKey, String comicId, String chapterId) async {
    if (!_loadedRules.contains(ruleKey)) {
      final loaded = await loadRule(ruleKey);
      if (!loaded) {
        Logger.warning('规则加载失败，无法获取章节: $ruleKey');
        return [];
      }
    }

    final ruleInfo = _availableRules[ruleKey];
    if (ruleInfo?.type == 'json') {
      final jsonEngine = _jsonEngines[ruleKey];
      if (jsonEngine != null) {
        return await jsonEngine.getImages(comicId, chapterId: chapterId);
      }
    } else {
      Logger.warning('不支持的规则类型: ${ruleInfo?.type}');
    }
    return [];
  }

  /// 获取指定规则的基础URL（用于 Referer 等）
  String? getBaseUrl(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    if (engine == null) return null;
    return engine.baseUrl;
  }

  /// 获取阅读器 CDN 回退列表
  List<String>? getReaderCdnFallbacks(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    if (engine == null) return null;
    final reader = engine.rule['reader'];
    if (reader is Map && reader['cdnFallbacks'] is List) {
      return List<String>.from(reader['cdnFallbacks'] as List);
    }
    return null;
  }

  /// 获取阅读器 Referer（若规则未定义，默认返回 baseUrl）
  String? getReaderReferer(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    if (engine == null) return null;
    final reader = engine.rule['reader'];
    if (reader is Map && reader['referer'] != null) {
      return reader['referer']?.toString();
    }
    return engine.baseUrl;
  }

  Map<String, String>? getReaderHeaders(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    if (engine == null) return null;
    final reader = engine.rule['reader'];
    if (reader is! Map) return null;
    final headers = reader['headers'];
    if (headers is! Map) return null;
    return headers.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  bool getUseWebview(String ruleKey) {
    final engine = _jsonEngines[ruleKey];
    if (engine == null) return false;
    return engine.rule['useWebview'] == true;
  }

  /// 获取规则统计信息
  Map<String, dynamic> getStats() {
    return {
      'availableCount': _availableRules.length,
      'loadedCount': _loadedRules.length,
      'availableRules': _availableRules.keys.toList(),
      'loadedRules': _loadedRules.toList(),
    };
  }

  /// 清理所有规则
  void clearAll() {
    _jsonEngines.clear();
    _loadedRules.clear();
    Logger.info('清理所有漫画规则');
  }

  /// 提取JS规则中的基本字段（保留用于手动转换参考）
  String? _extractJsField(String jsContent, String fieldName) {
    // 尝试匹配双引号
    final doubleQuotePattern = RegExp('$fieldName\\s*=\\s*"([^"]+)"');
    final doubleQuoteMatch = doubleQuotePattern.firstMatch(jsContent);
    if (doubleQuoteMatch != null) {
      return doubleQuoteMatch.group(1);
    }
    
    // 尝试匹配单引号
    final singleQuotePattern = RegExp("$fieldName\\s*=\\s*'([^']+)'");
    final singleQuoteMatch = singleQuotePattern.firstMatch(jsContent);
    if (singleQuoteMatch != null) {
      return singleQuoteMatch.group(1);
    }
    
    // 尝试匹配冒号语法
    final colonDoubleQuotePattern = RegExp('$fieldName\\s*:\\s*"([^"]+)"');
    final colonDoubleQuoteMatch = colonDoubleQuotePattern.firstMatch(jsContent);
    if (colonDoubleQuoteMatch != null) {
      return colonDoubleQuoteMatch.group(1);
    }
    
    final colonSingleQuotePattern = RegExp("$fieldName\\s*:\\s*'([^']+)'");
    final colonSingleQuoteMatch = colonSingleQuotePattern.firstMatch(jsContent);
    if (colonSingleQuoteMatch != null) {
      return colonSingleQuoteMatch.group(1);
    }
    
    return null;
  }


}