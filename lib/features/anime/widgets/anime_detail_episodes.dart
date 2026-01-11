import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../../../core/models/anime_item.dart';
import '../anime_store.dart';
import '../player/video_player_page.dart';

/// 动漫详情剧集标签页
class AnimeDetailEpisodes extends StatelessWidget {
  final AnimeItem animeItem;
  final AnimeStore store;

  const AnimeDetailEpisodes({
    super.key,
    required this.animeItem,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final animeDetail = store.currentAnimeDetail;

        if (store.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载剧集信息...'),
              ],
            ),
          );
        }

        if (animeDetail == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '无法加载剧集信息',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      store.error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => store.getAnimeDetail(animeItem),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        if (animeDetail.episodes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.movie_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无剧集信息',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '该动漫可能还未更新或规则解析失败',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // 按线路分组剧集
        final episodesByRoad = <int, List<AnimeEpisode>>{};
        for (final episode in animeDetail.episodes) {
          episodesByRoad.putIfAbsent(episode.roadIndex, () => []).add(episode);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 剧集统计信息
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '共 ${animeDetail.episodes.length} 集',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          if (episodesByRoad.length > 1)
                            Text(
                              '${episodesByRoad.length} 个播放线路',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 按线路显示剧集
              ...episodesByRoad.entries.map((entry) {
                final roadIndex = entry.key;
                final episodes = entry.value;
                
                // 按集数排序
                episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 线路标题
                    if (episodesByRoad.length > 1) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '线路 ${roadIndex + 1}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],

                    // 剧集网格
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6, // 每行6个剧集按钮
                        childAspectRatio: 2.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: episodes.length,
                      itemBuilder: (context, index) {
                        final episode = episodes[index];
                        return _EpisodeButton(
                          episode: episode,
                          onTap: () => _playEpisode(context, episode),
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// 播放剧集
  void _playEpisode(BuildContext context, AnimeEpisode episode) {
    // 导航到播放器页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          episode: episode,
          animeTitle: animeItem.displayTitle,
          ruleKey: animeItem.ruleKey, // 传递规则键
        ),
      ),
    );
  }
}

/// 剧集按钮组件
class _EpisodeButton extends StatelessWidget {
  final AnimeEpisode episode;
  final VoidCallback onTap;

  const _EpisodeButton({
    required this.episode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '第${episode.episodeNumber}集',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}