import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../../core/services/cache_service.dart';
import '../home_store.dart';

/// 首页内容
class HomeContent extends StatelessWidget {
  final HomeStore store;

  const HomeContent({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final theme = Theme.of(context);
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 页面标题
              Text(
                '欢迎使用 AuriLight',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                '统一的动漫和漫画观看平台',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 统计卡片
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      title: '动漫源',
                      count: store.animeRulesCount,
                      icon: Icons.play_arrow,
                      color: Colors.blue,
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  Expanded(
                    child: _buildStatCard(
                      context,
                      title: '漫画源',
                      count: store.mangaRulesCount,
                      icon: Icons.book,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // 快速操作
              Text(
                '快速操作',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              
              const SizedBox(height: 16),
              
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildQuickActionChip(
                    context,
                    label: 'JS引擎测试',
                    icon: Icons.bug_report,
                    onTap: () {
                      Modular.to.pushNamed('/test');
                    },
                  ),
                  _buildQuickActionChip(
                    context,
                    label: '添加规则源',
                    icon: Icons.add,
                    onTap: () {
                      // TODO: 实现添加规则源
                    },
                  ),
                  _buildQuickActionChip(
                    context,
                    label: '导入收藏',
                    icon: Icons.file_upload,
                    onTap: () {
                      // TODO: 实现导入收藏
                    },
                  ),
                  _buildQuickActionChip(
                    context,
                    label: '清理缓存',
                    icon: Icons.cleaning_services,
                    onTap: () => _showClearCacheDialog(context),
                  ),
                ],
              ),
              
              const SizedBox(height: 64),
              
              // 版本信息
              Center(
                child: Text(
                  'AuriLight v1.0.0',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Text(
              count.toString(),
              style: theme.textTheme.headlineLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建快速操作芯片
  Widget _buildQuickActionChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }

  /// 显示清理缓存确认对话框
  void _showClearCacheDialog(BuildContext context) {
    final cacheService = CacheService();
    
    // 直接显示带有 FutureBuilder 的对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FutureBuilder<String>(
        future: cacheService.getFormattedCacheSize(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return AlertDialog(
            title: const Text('清理缓存'),
            content: Text('确认清除缓存 ${snapshot.data} 吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('否'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _executeClearCache(context, cacheService);
                },
                child: const Text('是'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 执行清理缓存
  void _executeClearCache(BuildContext context, CacheService cacheService) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) {
        // 执行清理并自动关闭
        cacheService.clearAllCache().then((_) {
          Navigator.of(loadingContext).pop();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('缓存清理完成'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        });
        
        return const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在清理缓存...'),
            ],
          ),
        );
      },
    );
  }
}