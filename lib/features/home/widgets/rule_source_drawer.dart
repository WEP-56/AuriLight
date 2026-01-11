import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_core/simple_live_core.dart';
import '../../../core/services/live_manager.dart';

/// 规则源选择抽屉
class RuleSourceDrawer extends StatefulWidget {
  final Function(String ruleKey, String ruleType) onRuleSelected;
  final Function(String platformId)? onLivePlatformSelected;

  const RuleSourceDrawer({
    super.key,
    required this.onRuleSelected,
    this.onLivePlatformSelected,
  });

  @override
  State<RuleSourceDrawer> createState() => _RuleSourceDrawerState();
}

class _RuleSourceDrawerState extends State<RuleSourceDrawer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RuleSourceInfo> _animeRules = [];
  List<RuleSourceInfo> _comicRules = [];
  List<LiveSite> _livePlatforms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRuleSources();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载规则源列表
  Future<void> _loadRuleSources() async {
    setState(() => _isLoading = true);
    
    try {
      // 加载动画规则
      _animeRules = await _loadAnimeRules();
      
      // 加载漫画规则
      _comicRules = await _loadMangaRules();
      
      // 加载直播平台
      _livePlatforms = await _loadLivePlatforms();
      
    } catch (e) {
      debugPrint('加载规则源失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 加载动画规则源
  Future<List<RuleSourceInfo>> _loadAnimeRules() async {
    final List<RuleSourceInfo> rules = [];
    
    // 自动扫描assets/rules/anime目录中的所有.json文件
    try {
      // 获取AssetManifest来列出所有assets文件
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      // 过滤出anime规则文件
      final animeRuleFiles = manifestMap.keys
          .where((String key) => key.startsWith('assets/rules/anime/') && key.endsWith('.json'))
          .where((String key) => !key.endsWith('index.json')) // 排除index.json
          .toList();
      
      print('[规则源扫描] 发现 ${animeRuleFiles.length} 个动画规则文件');
      
      // 加载每个规则文件
      for (final assetPath in animeRuleFiles) {
        try {
          final ruleContent = await rootBundle.loadString(assetPath);
          final ruleData = json.decode(ruleContent);
          
          // 从文件路径提取规则key
          final fileName = assetPath.split('/').last;
          final ruleKey = fileName.substring(0, fileName.length - 5); // 移除.json后缀
          
          rules.add(RuleSourceInfo(
            key: ruleKey,
            name: ruleData['name'] ?? ruleKey,
            version: ruleData['version'] ?? '1.0',
            baseURL: ruleData['baseURL'] ?? '',
            description: _generateDescription(ruleData),
            useWebview: ruleData['useWebview'] == true,
            type: 'anime',
          ));
          
          print('[规则源扫描] 成功加载规则: $ruleKey (${ruleData['name'] ?? ruleKey})');
        } catch (e) {
          // 如果规则文件解析失败，跳过并记录错误
          final fileName = assetPath.split('/').last;
          print('[规则源扫描] 跳过无效规则文件 $fileName: $e');
        }
      }
      
      // 按名称排序
      rules.sort((a, b) => a.name.compareTo(b.name));
      
      print('[规则源扫描] 成功加载 ${rules.length} 个动画规则源');
    } catch (e) {
      print('[规则源扫描] 扫描失败: $e');
      
      // 如果自动扫描失败，回退到预定义列表
      return await _loadPredefinedAnimeRules();
    }
    
    return rules;
  }

  /// 加载预定义的动画规则源（回退方案）
  Future<List<RuleSourceInfo>> _loadPredefinedAnimeRules() async {
    final List<RuleSourceInfo> rules = [];
    
    // 预定义的规则源列表（从assets中加载）
    final predefinedRules = [
      '1ANI', '295yhw', '7sefun', '9ciyuan', 'aafun', 'AGE', 'akianime',
      'anime7', 'ant', 'aowu', 'BF', 'bobodm', 'brovod', 'cyfz', 'dlma',
      'DM84', 'eacg', 'Fantuan', 'FQDM', 'giriGiriLove', 'gugu3', 'hfkzm',
      'HZDM', 'jzsdm', 'k8dm', 'kimani', 'libvio', 'LMM', 'mandao',
      'mitaodm', 'MT', 'mwcy', 'MXdm', 'NT', 'omofun03', 'pekolove',
      'qifun', 'qkan9', 'skr', 'tt776b', 'xfdm', 'xiapidm', 'xigua',
      'yishijie', 'ylsp', 'zkk79',
    ];
    
    print('[规则源扫描] 使用预定义规则列表，共 ${predefinedRules.length} 个');
    
    // 尝试加载每个预定义的规则
    for (final ruleKey in predefinedRules) {
      try {
        final assetPath = 'assets/rules/anime/$ruleKey.json';
        final ruleContent = await rootBundle.loadString(assetPath);
        final ruleData = json.decode(ruleContent);
        
        rules.add(RuleSourceInfo(
          key: ruleKey,
          name: ruleData['name'] ?? ruleKey,
          version: ruleData['version'] ?? '1.0',
          baseURL: ruleData['baseURL'] ?? '',
          description: _generateDescription(ruleData),
          useWebview: ruleData['useWebview'] == true,
          type: 'anime',
        ));
      } catch (e) {
        // 如果规则文件不存在或解析失败，跳过
        debugPrint('跳过规则 $ruleKey: $e');
      }
    }
    
    return rules;
  }

  /// 生成规则描述
  String _generateDescription(Map<String, dynamic> ruleData) {
    final features = <String>[];
    
    if (ruleData['useWebview'] == true) {
      features.add('WebView解析');
    }
    if (ruleData['muliSources'] == true) {
      features.add('多线路');
    }
    if (ruleData['useNativePlayer'] == true) {
      features.add('原生播放器');
    }
    
    return features.isEmpty ? '标准规则' : features.join(' • ');
  }

  /// 加载漫画规则源（仅JSON规则）
  Future<List<RuleSourceInfo>> _loadMangaRules() async {
    final List<RuleSourceInfo> rules = [];
    
    // 使用预定义的漫画规则列表（仅JSON）
    try {
      // 预定义的漫画规则文件列表（仅JSON）
      final predefinedMangaRules = [
        'baihehui', 'baozi', 'ccc', 'comic_walker', 'comick', 'copy_manga',
        'ehentai', 'example_manga', 'goda', 'hcomic', 'hitomi', 'ikmmh',
        'jm', 'komga', 'komiic', 'lanraragi', 'manga_dex', 'manhuagui',
        'manhuaren', 'manwaba', 'mh1234', 'mh18', 'mxs', 'nhentai',
        'picacg', 'shonen_jump_plus', 'wnacg', 'ykmh', 'zaimanhua',
      ];
      
      debugPrint('[漫画规则扫描] 扫描预定义JSON漫画规则，共 ${predefinedMangaRules.length} 个');
      
      // 加载每个预定义的规则文件（仅JSON）
      for (final ruleKey in predefinedMangaRules) {
        try {
          // 优先尝试转换后的JSON文件
          String assetPath = 'assets/rules/manga/${ruleKey}_converted.json';
          String ruleContent;
          
          try {
            ruleContent = await rootBundle.loadString(assetPath);
          } catch (e) {
            // 如果转换后的文件不存在，尝试原始JSON文件
            assetPath = 'assets/rules/manga/$ruleKey.json';
            ruleContent = await rootBundle.loadString(assetPath);
          }
          
          // 解析JSON规则信息
          final ruleData = json.decode(ruleContent);
          
          rules.add(RuleSourceInfo(
            key: ruleKey,
            name: ruleData['displayName'] ?? ruleData['name'] ?? ruleKey,
            version: ruleData['version'] ?? '1.0',
            baseURL: ruleData['baseURL'] ?? '',
            description: _generateJsonMangaDescription(ruleData),
            useWebview: false, // JSON规则不使用WebView
            type: 'manga',
          ));
          
          debugPrint('[漫画规则扫描] 成功加载JSON规则: $ruleKey (${ruleData['displayName'] ?? ruleData['name'] ?? ruleKey})');
        } catch (e) {
          // 如果规则文件解析失败，跳过并记录错误
          debugPrint('[漫画规则扫描] 跳过无效JSON规则文件 $ruleKey: $e');
        }
      }
      
      // 按名称排序
      rules.sort((a, b) => a.name.compareTo(b.name));
      
      debugPrint('[漫画规则扫描] 成功加载 ${rules.length} 个JSON漫画规则源');
    } catch (e) {
      debugPrint('[漫画规则扫描] 扫描失败: $e');
    }
    
    return rules;
  }

  /// 生成JSON漫画规则描述
  String _generateJsonMangaDescription(Map<String, dynamic> ruleData) {
    final features = <String>['JSON规则'];
    
    if (ruleData['baseURL']?.toString().isNotEmpty == true) {
      features.add('在线源');
    }
    
    if (ruleData['domainRefresh']?['enabled'] == true) {
      features.add('域名刷新');
    }
    
    if (ruleData['login']?['enabled'] == true) {
      features.add('需要登录');
    }
    
    return features.join(' • ');
  }

  /// 加载直播平台
  Future<List<LiveSite>> _loadLivePlatforms() async {
    try {
      // 初始化直播管理器
      await LiveManager().initialize();
      
      // 获取所有直播平台
      final platforms = LiveManager().allSites;
      
      debugPrint('[直播平台扫描] 成功加载 ${platforms.length} 个直播平台');
      
      return platforms;
    } catch (e) {
      debugPrint('[直播平台扫描] 加载失败: $e');
      return [];
    }
  }

  /// 解析漫画规则信息（保留用于参考）
  Map<String, String> _parseMangaRuleInfo(String content, String defaultKey) {
    final info = <String, String>{};
    
    try {
      // 使用正则表达式提取基本信息 - 分别处理双引号和单引号
      RegExpMatch? nameMatch = RegExp(r'name\s*=\s*"([^"]+)"').firstMatch(content);
      nameMatch ??= RegExp(r"name\s*=\s*'([^']+)'").firstMatch(content);
      
      RegExpMatch? keyMatch = RegExp(r'key\s*=\s*"([^"]+)"').firstMatch(content);
      keyMatch ??= RegExp(r"key\s*=\s*'([^']+)'").firstMatch(content);
      
      RegExpMatch? versionMatch = RegExp(r'version\s*=\s*"([^"]+)"').firstMatch(content);
      versionMatch ??= RegExp(r"version\s*=\s*'([^']+)'").firstMatch(content);
      
      RegExpMatch? urlMatch = RegExp(r'url\s*=\s*"([^"]+)"').firstMatch(content);
      urlMatch ??= RegExp(r"url\s*=\s*'([^']+)'").firstMatch(content);
      
      info['name'] = nameMatch?.group(1) ?? defaultKey;
      info['key'] = keyMatch?.group(1) ?? defaultKey;
      info['version'] = versionMatch?.group(1) ?? '1.0.0';
      info['url'] = urlMatch?.group(1) ?? '';
    } catch (e) {
      debugPrint('解析漫画规则信息失败: $e');
      info['name'] = defaultKey;
      info['key'] = defaultKey;
      info['version'] = '1.0.0';
      info['url'] = '';
    }
    
    return info;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 抽屉顶部
          _buildDrawerHeader(),
          
          // 标签栏
          _buildTabBar(),
          
          // 内容区域
          Expanded(
            child: _isLoading
                ? _buildLoadingWidget()
                : _buildTabBarView(),
          ),
        ],
      ),
    );
  }

  /// 构建抽屉头部
  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.rule,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            '选择规则源',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  /// 构建标签栏
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(
            icon: Icon(Icons.play_circle_outline),
            text: '动画',
          ),
          Tab(
            icon: Icon(Icons.menu_book_outlined),
            text: '漫画',
          ),
          Tab(
            icon: Icon(Icons.live_tv),
            text: '直播',
          ),
        ],
      ),
    );
  }

  /// 构建标签页视图
  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildRuleList(_animeRules, 'anime'),
        _buildRuleList(_comicRules, 'comic'),
        _buildLivePlatformList(),
      ],
    );
  }

  /// 构建规则列表
  Widget _buildRuleList(List<RuleSourceInfo> rules, String type) {
    if (rules.isEmpty) {
      return _buildEmptyWidget(type);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return _buildRuleCard(rule);
      },
    );
  }

  /// 构建规则卡片
  Widget _buildRuleCard(RuleSourceInfo rule) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // 直接选择规则，不再进行转换
          widget.onRuleSelected(rule.key, rule.type);
          Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 规则名称和版本
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'v${rule.version}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 基础URL
              if (rule.baseURL.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        rule.baseURL,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              
              // 特性描述
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      rule.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              
              // WebView标识
              if (rule.useWebview) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.web,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'WebView',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建空状态组件
  Widget _buildEmptyWidget(String type) {
    final typeName = type == 'anime' ? '动画' : type == 'comic' ? '漫画' : '直播';
    final icon = type == 'anime' 
        ? Icons.play_circle_outline 
        : type == 'comic' 
            ? Icons.menu_book_outlined 
            : Icons.live_tv;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无${typeName}规则源',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            type == 'live' 
                ? '直播平台初始化失败，请重试'
                : '请将JSON规则文件放入 assets/rules/${type}/ 目录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 构建直播平台列表
  Widget _buildLivePlatformList() {
    if (_livePlatforms.isEmpty) {
      return _buildEmptyWidget('live');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _livePlatforms.length,
      itemBuilder: (context, index) {
        final platform = _livePlatforms[index];
        return _buildLivePlatformCard(platform);
      },
    );
  }

  /// 构建直播平台卡片
  Widget _buildLivePlatformCard(LiveSite platform) {
    final isLoggedIn = LiveManager().isLoggedIn(platform.id);
    final supportsLogin = LiveManager().supportsCookieLogin(platform.id);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // 选择直播平台
          if (widget.onLivePlatformSelected != null) {
            widget.onLivePlatformSelected!(platform.id);
          }
          Navigator.of(context).pop();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 平台名称和登录状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      platform.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (supportsLogin) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLoggedIn 
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isLoggedIn ? '已登录' : '未登录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isLoggedIn 
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 平台ID
              Row(
                children: [
                  Icon(
                    Icons.tag,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    platform.id,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 4),
              
              // 特性描述
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supportsLogin ? '支持登录 • 直播搜索 • 分类浏览' : '直播搜索 • 分类浏览',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  /// 构建加载组件
  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在扫描规则源...'),
        ],
      ),
    );
  }
}

/// 规则源信息
class RuleSourceInfo {
  final String key;
  final String name;
  final String version;
  final String baseURL;
  final String description;
  final bool useWebview;
  final String type;

  RuleSourceInfo({
    required this.key,
    required this.name,
    required this.version,
    required this.baseURL,
    required this.description,
    required this.useWebview,
    required this.type,
  });
}