import 'package:hive/hive.dart';

part 'unified_rule.g.dart';

/// 统一规则类型
enum RuleType {
  anime,
  manga,
}

/// 统一规则结构 - 兼容 Kazumi JSON 和 Venera JS 规则
@HiveType(typeId: 10)
class UnifiedRule extends HiveObject {
  @HiveField(0)
  @override
  String key; // 唯一标识符
  
  @HiveField(1)
  String name; // 显示名称
  
  @HiveField(2)
  String version; // 版本号
  
  @HiveField(3)
  RuleType type; // 规则类型：anime 或 manga
  
  @HiveField(4)
  String baseUrl; // 基础URL
  
  @HiveField(5)
  String? icon; // 图标URL或路径
  
  @HiveField(6)
  bool enabled; // 是否启用
  
  @HiveField(7)
  int sortOrder; // 排序顺序（用于侧边栏拖拽）
  
  @HiveField(8)
  String filePath; // 原始规则文件路径
  
  @HiveField(9)
  String fileType; // 文件类型：js 或 json
  
  @HiveField(10)
  Map<String, dynamic> rawData; // 原始规则数据
  
  @HiveField(11)
  Map<String, dynamic>? settings; // 规则设置项
  
  @HiveField(12)
  DateTime createdAt; // 创建时间
  
  @HiveField(13)
  DateTime updatedAt; // 更新时间
  
  // 搜索相关配置
  @HiveField(14)
  SearchConfig? searchConfig;
  
  // 详情页配置
  @HiveField(15)
  DetailConfig? detailConfig;
  
  // 播放/阅读配置
  @HiveField(16)
  PlayConfig? playConfig;
  
  // 账户配置（用于需要登录的源）
  @HiveField(17)
  AccountConfig? accountConfig;

  // 规则特定配置
  @HiveField(18)
  String? userAgent; // 自定义User-Agent
  
  @HiveField(19)
  String? referer; // 自定义Referer
  
  @HiveField(20)
  bool useLegacyParser; // 使用旧版解析器
  
  @HiveField(21)
  bool adBlocker; // 启用广告拦截器

  UnifiedRule({
    required this.key,
    required this.name,
    required this.version,
    required this.type,
    required this.baseUrl,
    this.icon,
    this.enabled = true,
    this.sortOrder = 0,
    required this.filePath,
    required this.fileType,
    required this.rawData,
    this.settings,
    required this.createdAt,
    required this.updatedAt,
    this.searchConfig,
    this.detailConfig,
    this.playConfig,
    this.accountConfig,
    this.userAgent,
    this.referer,
    this.useLegacyParser = false,
    this.adBlocker = false,
  });

  /// 从 Kazumi JSON 规则创建
  factory UnifiedRule.fromKazumiJson(Map<String, dynamic> json, String filePath) {
    return UnifiedRule(
      key: json['name'] ?? 'unknown',
      name: json['name'] ?? 'Unknown',
      version: json['version'] ?? '1.0.0',
      type: RuleType.anime,
      baseUrl: json['baseURL'] ?? '',
      enabled: true,
      sortOrder: 0,
      filePath: filePath,
      fileType: 'json',
      rawData: json,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      searchConfig: SearchConfig.fromKazumiJson(json),
      detailConfig: DetailConfig.fromKazumiJson(json),
      playConfig: PlayConfig.fromKazumiJson(json),
      userAgent: json['userAgent']?.isEmpty == true ? null : json['userAgent'],
      referer: json['referer']?.isEmpty == true ? null : json['referer'],
      useLegacyParser: json['useLegacyParser'] ?? false,
      adBlocker: json['adBlocker'] ?? false,
    );
  }

  factory UnifiedRule.fromVeneraJson(Map<String, dynamic> json, String filePath) {
    return UnifiedRule(
      key: json['name']?.toString() ?? 'unknown',
      name: json['displayName']?.toString() ?? json['name']?.toString() ?? 'Unknown',
      version: json['version']?.toString() ?? '1.0.0',
      type: RuleType.manga,
      baseUrl: json['baseURL']?.toString() ?? '',
      enabled: true,
      sortOrder: 0,
      filePath: filePath,
      fileType: 'json',
      rawData: json,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      accountConfig: (json['account'] is Map)
          ? AccountConfig(
              requiresLogin: true,
              loginConfig: (json['account'] as Map).cast<String, dynamic>(),
            )
          : null,
      userAgent: json['userAgent']?.toString().isEmpty == true ? null : json['userAgent']?.toString(),
      referer: json['referer']?.toString().isEmpty == true ? null : json['referer']?.toString(),
    );
  }

  /// 从 Venera JS 规则创建
  factory UnifiedRule.fromVeneraJs(Map<String, dynamic> metadata, String filePath) {
    return UnifiedRule(
      key: metadata['key'] ?? 'unknown',
      name: metadata['name'] ?? 'Unknown',
      version: metadata['version'] ?? '1.0.0',
      type: RuleType.manga,
      baseUrl: metadata['baseUrl'] ?? '',
      enabled: true,
      sortOrder: 0,
      filePath: filePath,
      fileType: 'js',
      rawData: metadata,
      settings: metadata['settings'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      accountConfig: metadata['account'] != null 
        ? AccountConfig.fromVeneraJs(metadata['account']) 
        : null,
    );
  }

  /// 更新排序顺序
  void updateSortOrder(int newOrder) {
    sortOrder = newOrder;
    updatedAt = DateTime.now();
    save();
  }

  /// 切换启用状态
  void toggleEnabled() {
    enabled = !enabled;
    updatedAt = DateTime.now();
    save();
  }
}

/// 搜索配置
@HiveType(typeId: 11)
class SearchConfig {
  @HiveField(0)
  String searchUrl; // 搜索URL模板
  
  @HiveField(1)
  String? searchList; // 搜索结果列表选择器
  
  @HiveField(2)
  String? searchName; // 标题选择器
  
  @HiveField(3)
  String? searchResult; // 链接选择器
  
  @HiveField(4)
  String? searchCover; // 封面选择器
  
  @HiveField(5)
  bool usePost; // 是否使用POST请求
  
  @HiveField(6)
  Map<String, String>? headers; // 请求头

  SearchConfig({
    required this.searchUrl,
    this.searchList,
    this.searchName,
    this.searchResult,
    this.searchCover,
    this.usePost = false,
    this.headers,
  });

  factory SearchConfig.fromKazumiJson(Map<String, dynamic> json) {
    return SearchConfig(
      searchUrl: json['searchURL'] ?? '',
      searchList: json['searchList'],
      searchName: json['searchName'],
      searchResult: json['searchResult'],
      usePost: json['usePost'] ?? false,
    );
  }
}

/// 详情页配置
@HiveType(typeId: 12)
class DetailConfig {
  @HiveField(0)
  String? titleSelector; // 标题选择器
  
  @HiveField(1)
  String? coverSelector; // 封面选择器
  
  @HiveField(2)
  String? descriptionSelector; // 描述选择器
  
  @HiveField(3)
  String? tagsSelector; // 标签选择器
  
  @HiveField(4)
  String? chaptersSelector; // 章节列表选择器

  DetailConfig({
    this.titleSelector,
    this.coverSelector,
    this.descriptionSelector,
    this.tagsSelector,
    this.chaptersSelector,
  });

  factory DetailConfig.fromKazumiJson(Map<String, dynamic> json) {
    return DetailConfig(
      chaptersSelector: json['chapterRoads'],
    );
  }
}

/// 播放/阅读配置
@HiveType(typeId: 13)
class PlayConfig {
  @HiveField(0)
  String? playUrlSelector; // 播放链接选择器
  
  @HiveField(1)
  String? imageListSelector; // 图片列表选择器（漫画）
  
  @HiveField(2)
  bool useWebview; // 是否使用WebView
  
  @HiveField(3)
  bool useNativePlayer; // 是否使用原生播放器
  
  @HiveField(4)
  String? referer; // Referer头

  PlayConfig({
    this.playUrlSelector,
    this.imageListSelector,
    this.useWebview = false,
    this.useNativePlayer = true,
    this.referer,
  });

  factory PlayConfig.fromKazumiJson(Map<String, dynamic> json) {
    return PlayConfig(
      playUrlSelector: json['chapterResult'],
      useWebview: json['useWebview'] ?? false,
      useNativePlayer: json['useNativePlayer'] ?? true,
      referer: json['referer'],
    );
  }
}

/// 账户配置
@HiveType(typeId: 14)
class AccountConfig {
  @HiveField(0)
  bool requiresLogin; // 是否需要登录
  
  @HiveField(1)
  String? loginUrl; // 登录页面URL
  
  @HiveField(2)
  String? registerUrl; // 注册页面URL
  
  @HiveField(3)
  Map<String, dynamic>? loginConfig; // 登录配置

  AccountConfig({
    this.requiresLogin = false,
    this.loginUrl,
    this.registerUrl,
    this.loginConfig,
  });

  factory AccountConfig.fromVeneraJs(Map<String, dynamic> account) {
    return AccountConfig(
      requiresLogin: true,
      registerUrl: account['registerWebsite'],
      loginConfig: account,
    );
  }
}