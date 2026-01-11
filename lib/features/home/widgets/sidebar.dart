import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../home_store.dart';
import '../../../core/models/unified_rule.dart';
import '../../../core/services/live_manager.dart';
import 'rule_source_drawer.dart';

/// 应用侧边栏 - 支持热插拔源管理
class AppSidebar extends StatefulWidget {
  final HomeStore store;

  const AppSidebar({
    super.key,
    required this.store,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _livePlatformsInitialized = false;

  @override
  void initState() {
    super.initState();
    _initLivePlatforms();
  }

  Future<void> _initLivePlatforms() async {
    await LiveManager().initialize();
    if (mounted) {
      setState(() => _livePlatformsInitialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // 应用标题栏
          _buildAppHeader(context),
          
          // 可滚动的内容区域
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 导航菜单
                  _buildNavigationMenu(context),
                  
                  const Divider(),
                  
                  // 直播平台列表（始终显示）
                  if (_livePlatformsInitialized)
                    _buildLivePlatformsList(context),
                  
                  const Divider(),
                  
                  // 规则源列表
                  _buildRulesList(context),
                ],
              ),
            ),
          ),
          
          // 底部操作按钮
          _buildBottomActions(context),
        ],
      ),
    );
  }

  /// 构建应用标题栏
  Widget _buildAppHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    
    return GestureDetector(
      // 桌面平台支持拖动窗口
      onPanStart: isDesktop ? (_) => windowManager.startDragging() : null,
      onDoubleTap: isDesktop ? () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      } : null,
      child: Container(
        height: 60,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
        ),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_filled,
              color: theme.colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'AuriLight',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建导航菜单
  Widget _buildNavigationMenu(BuildContext context) {
    return Observer(
      builder: (context) {
        return Column(
          children: [
            _buildNavigationItem(
              context,
              icon: Icons.home,
              title: '首页',
              isSelected: widget.store.selectedIndex == 0,
              onTap: () => widget.store.selectItem(0),
            ),
            _buildNavigationItem(
              context,
              icon: Icons.favorite,
              title: '收藏',
              isSelected: widget.store.selectedIndex == 1,
              onTap: () => widget.store.selectItem(1),
            ),
            _buildNavigationItem(
              context,
              icon: Icons.download,
              title: '下载',
              isSelected: widget.store.selectedIndex == 2,
              onTap: () => widget.store.selectItem(2),
            ),
            _buildNavigationItem(
              context,
              icon: Icons.history,
              title: '历史',
              isSelected: widget.store.selectedIndex == 3,
              onTap: () => widget.store.selectItem(3),
            ),
            _buildNavigationItem(
              context,
              icon: Icons.settings,
              title: '设置',
              isSelected: widget.store.selectedIndex == 4,
              onTap: () => widget.store.selectItem(4),
            ),
          ],
        );
      },
    );
  }

  /// 构建导航项
  Widget _buildNavigationItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected 
          ? theme.colorScheme.primary 
          : theme.colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected 
            ? theme.colorScheme.primary 
            : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: onTap,
      dense: true,
    );
  }

  /// 构建直播平台列表
  Widget _buildLivePlatformsList(BuildContext context) {
    final platforms = LiveManager().allSites;
    
    return Observer(
      builder: (context) {
        final currentRoute = widget.store.currentRoute;
        final isLiveRoute = currentRoute.startsWith('/live/');
        final currentPlatformId = isLiveRoute ? currentRoute.replaceFirst('/live/', '') : null;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.live_tv, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '直播平台',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${platforms.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            ...platforms.map((platform) {
              final isSelected = platform.id == currentPlatformId;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected 
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.live_tv,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                    size: 20,
                  ),
                ),
                title: Text(
                  platform.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                selected: isSelected,
                selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                onTap: () {
                  // 切换直播平台
                  LiveManager().setCurrentSite(platform.id);
                  widget.store.setCurrentRoute('/live/${platform.id}');
                },
                dense: true,
              );
            }),
          ],
        );
      },
    );
  }

  /// 构建规则源列表
  Widget _buildRulesList(BuildContext context) {
    return Observer(
      builder: (context) {
        final rules = widget.store.enabledRules;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 规则源标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.source, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '规则源',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${rules.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            // 规则列表
            if (rules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.source, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        '暂无可用规则源',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...rules.map((rule) => _buildRuleItem(context, rule)),
          ],
        );
      },
    );
  }

  /// 构建规则项
  Widget _buildRuleItem(BuildContext context, UnifiedRule rule) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rule.type == RuleType.anime 
            ? Colors.blue.withValues(alpha: 0.2)
            : Colors.green.withValues(alpha: 0.2),
          child: Icon(
            rule.type == RuleType.anime ? Icons.play_arrow : Icons.book,
            color: rule.type == RuleType.anime ? Colors.blue : Colors.green,
            size: 20,
          ),
        ),
        title: Text(
          rule.name,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          rule.type == RuleType.anime ? '动漫' : '漫画',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 启用/禁用开关
            Switch(
              value: rule.enabled,
              onChanged: widget.store.isSearching ? null : (_) => widget.store.toggleRuleEnabled(rule.key),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            
            // 删除按钮
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: widget.store.isSearching ? null : () => _showDeleteRuleDialog(context, rule),
              tooltip: widget.store.isSearching ? '搜索中，请稍候...' : '删除规则源',
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              padding: const EdgeInsets.all(4),
            ),
          ],
        ),
        onTap: widget.store.isSearching ? null : () {
          // 导航到对应的规则页面
          if (rule.type == RuleType.anime) {
            widget.store.navigateToAnime(rule.key);
          } else {
            // 漫画页面导航
            widget.store.setCurrentRoute('/manga/${rule.key}');
          }
        },
        dense: true,
      ),
    );
  }

  /// 构建底部操作按钮
  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 添加规则按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.store.isSearching ? null : () => _showAddRuleDialog(context),
              icon: const Icon(Icons.add),
              label: Text(widget.store.isSearching ? '搜索中...' : '添加规则源'),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 刷新按钮
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: widget.store.isSearching ? null : () => widget.store.refreshRules(),
              icon: const Icon(Icons.refresh),
              label: Text(widget.store.isSearching ? '搜索中...' : '刷新规则'),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示添加规则对话框
  void _showAddRuleDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RuleSourceDrawer(
        onRuleSelected: (ruleKey, ruleType) async {
          // 这里处理规则选择逻辑
          // 根据ruleKey和ruleType从assets中复制规则文件到本地
          await _addRuleFromAssets(context, ruleKey, ruleType);
        },
        onLivePlatformSelected: (platformId) {
          // 处理直播平台选择
          LiveManager().setCurrentSite(platformId);
          widget.store.setCurrentRoute('/live/$platformId');
        },
      ),
    );
  }

  /// 从assets添加规则
  Future<void> _addRuleFromAssets(BuildContext context, String ruleKey, String ruleType) async {
    try {
      String assetPath;
      String ruleContent;

      if (ruleType == 'anime') {
        assetPath = 'assets/rules/$ruleType/$ruleKey.json';
        ruleContent = await rootBundle.loadString(assetPath);
      } else {
        // 漫画规则统一使用JSON（优先转换后的 *_converted.json）
        try {
          assetPath = 'assets/rules/$ruleType/${ruleKey}_converted.json';
          ruleContent = await rootBundle.loadString(assetPath);
        } catch (_) {
          assetPath = 'assets/rules/$ruleType/$ruleKey.json';
          ruleContent = await rootBundle.loadString(assetPath);
        }
      }
      
      // 获取应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final rulesDir = Directory('${appDir.path}/rules');
      if (!await rulesDir.exists()) {
        await rulesDir.create(recursive: true);
      }
      
      // 写入规则文件
      final targetFile = File('${rulesDir.path}/$ruleKey.${ruleType == 'anime' ? 'json' : 'json'}');
      await targetFile.writeAsString(ruleContent);
      
      // 添加到规则管理器
      final success = await widget.store.importRuleFromFile(targetFile.path);
      
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('规则源 "$ruleKey" 添加成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (context.mounted) {
        throw Exception('添加规则失败');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('添加规则源失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 显示删除规则确认对话框
  void _showDeleteRuleDialog(BuildContext context, UnifiedRule rule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除规则源'),
        content: Text('确定要删除规则源 "${rule.name}" 吗？\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.store.deleteRule(rule.key);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
