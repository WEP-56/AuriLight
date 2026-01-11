import 'package:flutter/material.dart';

import '../anime_store.dart';
import '../../../core/models/anime_item.dart';

/// 动漫详情视图
class AnimeDetailView extends StatefulWidget {
  final AnimeDetail detail;
  final AnimeStore store;

  const AnimeDetailView({
    super.key,
    required this.detail,
    required this.store,
  });

  @override
  State<AnimeDetailView> createState() => _AnimeDetailViewState();
}

class _AnimeDetailViewState extends State<AnimeDetailView> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final isFav = await widget.store.isFavorited(widget.detail);
    if (mounted) {
      setState(() => _isFavorite = isFav);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final newStatus = await widget.store.toggleFavorite(widget.detail);
      if (mounted) {
        setState(() => _isFavorite = newStatus);
        // 使用 SnackBar 显示提示
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(newStatus ? '已添加到收藏' : '已取消收藏'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部工具栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    // 返回到搜索结果，而不是清空所有状态
                    widget.store.backToSearchResults();
                  },
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回搜索结果',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.detail.title,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : null,
                  ),
                  tooltip: _isFavorite ? '取消收藏' : '添加收藏',
                ),
              ],
            ),
          ),
          
          // 详情内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面和基本信息
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 封面
                      Container(
                        width: 120,
                        height: 160,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: widget.detail.coverUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  widget.detail.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(Icons.broken_image, size: 48),
                                    );
                                  },
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.movie, size: 48),
                              ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // 基本信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.detail.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.source,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.detail.ruleName,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.play_circle_outline,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.detail.episodes.length} 集',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  // 描述
                  if (widget.detail.description != null && widget.detail.description!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      '简介',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.detail.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  
                  // 章节列表
                  const SizedBox(height: 24),
                  Text(
                    '章节列表',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  
                  if (widget.detail.episodes.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('暂无章节信息'),
                      ),
                    )
                  else
                    _buildEpisodesList(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesList(BuildContext context) {
    // 按线路分组
    final Map<int, List<AnimeEpisode>> episodesByRoad = {};
    for (final episode in widget.detail.episodes) {
      episodesByRoad.putIfAbsent(episode.roadIndex, () => []).add(episode);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: episodesByRoad.entries.map((entry) {
        final roadIndex = entry.key;
        final episodes = entry.value;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (episodesByRoad.length > 1) ...[
              Text(
                '线路 ${roadIndex + 1}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
            ],
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: episodes.map((episode) {
                return ActionChip(
                  label: Text(episode.title),
                  onPressed: () => widget.store.playAnime(episode),
                  avatar: Icon(
                    Icons.play_arrow,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }).toList(),
            ),
            
            if (roadIndex < episodesByRoad.length - 1)
              const SizedBox(height: 16),
          ],
        );
      }).toList(),
    );
  }
}