import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import '../../../core/models/manga_item.dart';
import '../../../core/services/manga_image_provider.dart';
import '../manga_store.dart';

/// 漫画搜索结果组件 - 参考动画模块的响应式设计
class MangaSearchResults extends StatelessWidget {
  final MangaStore store;

  const MangaSearchResults({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final results = store.searchResults;

        if (results.isEmpty && !store.isSearching) {
          return _buildEmptyState(context);
        }

        return Column(
          children: [
            // 结果统计
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_stories,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '找到 ${results.length} 个结果',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  
                  // 搜索状态指示器
                  if (store.isSearching)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  
                  TextButton.icon(
                    onPressed: () => _clearResults(),
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
                  
                  return NotificationListener<ScrollNotification>(
                    onNotification: (scrollInfo) {
                      if (!store.isSearching && 
                          store.hasMorePages && 
                          scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: results.length + (store.isSearching ? 2 : 0),
                      itemBuilder: (context, index) {
                        if (index >= results.length) {
                          return _buildLoadingItem(context);
                        }
                        
                        final item = results[index];
                        return MangaItemCard(
                          item: item,
                          onTap: () => _navigateToDetail(context, item),
                          headers: store.getReaderHeadersForRule(store.selectedRuleKey),
                          referer: store.getReaderRefererForRule(store.selectedRuleKey),
                          cdnFallbacks: store.getCdnFallbacksForCurrentRule(),
                          forceWebView: store.getUseWebviewForRule(store.selectedRuleKey),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64),
          SizedBox(height: 16),
          Text('没有找到相关漫画'),
          Text('尝试使用其他关键词搜索'),
        ],
      ),
    );
  }

  Widget _buildLoadingItem(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  /// 清空搜索结果
  void _clearResults() {
    store.searchResults.clear();
  }

  /// 加载更多
  void _loadMore() {
    if (store.searchKeyword.isNotEmpty) {
      store.search(store.searchKeyword, loadMore: true);
    }
  }

  /// 导航到漫画详情页面
  void _navigateToDetail(BuildContext context, MangaItem item) {
    store.loadDetail(item.ruleKey, item.id);
  }
}

/// 漫画项目卡片 - 紧凑风格，参考动画模块设计
class MangaItemCard extends StatelessWidget {
  final MangaItem item;
  final VoidCallback onTap;
  final Map<String, String>? headers;
  final String? referer;
  final List<String>? cdnFallbacks;
  final bool forceWebView;

  const MangaItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.headers,
    this.referer,
    this.cdnFallbacks,
    this.forceWebView = false,
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
                    item.cover != null
                        ? MangaImage(
                            sourceKey: item.ruleKey,
                            imageUrl: item.cover!,
                            headers: headers,
                            referer: referer,
                            cdnFallbacks: cdnFallbacks,
                            forceWebView: forceWebView,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: _buildImagePlaceholder(context),
                            errorWidget: _buildImageError(context),
                          )
                        : _buildImagePlaceholder(context),
                    
                    // 评分标签 - 更小更紧凑
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
                                item.stars!.toStringAsFixed(1),
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
                    // 标题
                    Expanded(
                      child: Text(
                        item.title,
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

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories,
            size: 32,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '加载中...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageError(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 32,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 8),
          Text(
            '加载失败',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}