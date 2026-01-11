import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../anime_store.dart';
import '../../../core/models/anime_item.dart';
import '../pages/anime_detail_page.dart';
import 'html_content_dialog.dart';

/// 动漫搜索结果列表
class AnimeSearchResults extends StatelessWidget {
  final AnimeStore store;

  const AnimeSearchResults({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final results = store.searchResults;

        if (results.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 64),
                SizedBox(height: 16),
                Text('没有找到相关动漫'),
                Text('尝试使用其他关键词搜索'),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 结果统计
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.list,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '找到 ${results.length} 个结果',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  
                  // Bangumi集成状态指示器
                  if (store.isFetchingBangumi)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  
                  // Bangumi集成开关
                  IconButton(
                    onPressed: () => store.toggleBangumiIntegration(),
                    icon: Icon(
                      store.enableBangumiIntegration ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                      color: store.enableBangumiIntegration 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: store.enableBangumiIntegration ? '禁用Bangumi集成' : '启用Bangumi集成',
                  ),
                  
                  // HTML内容显示按钮
                  if (store.htmlContent != null) ...[
                    TextButton.icon(
                      onPressed: () => _showHtmlContent(context),
                      icon: const Icon(Icons.code),
                      label: const Text('HTML'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton.icon(
                    onPressed: () => store.clearSearchResults(),
                    icon: const Icon(Icons.clear),
                    label: const Text('清空'),
                  ),
                ],
              ),
            ),
            
            // 结果列表 - 响应式网格布局
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 根据屏幕宽度动态调整列数
                  int crossAxisCount;
                  double childAspectRatio;
                  
                  if (constraints.maxWidth > 1200) {
                    // 大屏幕：6列
                    crossAxisCount = 6;
                    childAspectRatio = 0.65;
                  } else if (constraints.maxWidth > 800) {
                    // 中等屏幕：4列
                    crossAxisCount = 4;
                    childAspectRatio = 0.6;
                  } else if (constraints.maxWidth > 600) {
                    // 小屏幕：3列
                    crossAxisCount = 3;
                    childAspectRatio = 0.65;
                  } else {
                    // 手机屏幕：2列
                    crossAxisCount = 2;
                    childAspectRatio = 0.7;
                  }
                  
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return AnimeItemCard(
                        item: item,
                        onTap: () => _navigateToDetail(context, item),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 显示HTML内容对话框
  void _showHtmlContent(BuildContext context) {
    if (store.htmlContent != null) {
      showDialog(
        context: context,
        builder: (context) => HtmlContentDialog(
          htmlContent: store.htmlContent!,
          title: '搜索页面HTML内容 - ${store.selectedRule?.name ?? "未知规则"}',
        ),
      );
    }
  }

  /// 导航到动漫详情页面
  void _navigateToDetail(BuildContext context, AnimeItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AnimeDetailPage(
          animeItem: item,
          store: store,
        ),
      ),
    );
  }
}

/// 动漫项目卡片 - 紧凑风格，参考Kazumi设计
class AnimeItemCard extends StatelessWidget {
  final AnimeItem item;
  final VoidCallback onTap;

  const AnimeItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero, // 移除默认边距
      elevation: 2, // 减少阴影
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // 减少圆角
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片 - 占据大部分空间
            Expanded(
              flex: 5, // 增加封面比例
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Stack(
                  children: [
                    // 封面图片
                    item.bestCoverUrl != null
                        ? Image.network(
                            item.bestCoverUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.broken_image, size: 32),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                          )
                        : const Center(
                            child: Icon(Icons.movie, size: 32),
                          ),
                    
                    // Bangumi评分标签 - 更小更紧凑
                    if (item.hasRating)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 10,
                              ),
                              const SizedBox(width: 1),
                              Text(
                                item.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Bangumi状态指示器 - 左下角
                    if (item.hasBangumiInfo || item.bangumiSearched)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: item.hasBangumiInfo ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // 标题区域 - 紧凑布局
            Expanded(
              flex: 2, // 减少标题区域比例
              child: Padding(
                padding: const EdgeInsets.all(6), // 减少内边距
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题（优先显示Bangumi中文名）
                    Expanded(
                      child: Text(
                        item.displayTitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.1, // 更紧凑的行高
                          fontSize: 11, // 稍微减小字体
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    const SizedBox(height: 2),
                    
                    // 规则源标签 - 更小更简洁
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.ruleName,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}