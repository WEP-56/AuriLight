import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../../../core/models/anime_item.dart';
import '../anime_store.dart';
import '../widgets/anime_detail_header.dart';
import '../widgets/anime_detail_summary.dart';
import '../widgets/anime_detail_episodes.dart';

/// 动漫详情页面
class AnimeDetailPage extends StatefulWidget {
  final AnimeItem animeItem;
  final AnimeStore store;

  const AnimeDetailPage({
    super.key,
    required this.animeItem,
    required this.store,
  });

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // 获取动漫详情
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.store.getAnimeDetail(widget.animeItem);
      _checkFavoriteStatus();
    });
  }

  Future<void> _checkFavoriteStatus() async {
    // 使用 AnimeItem 检查收藏状态
    final isFav = await widget.store.isFavoritedFromItem(widget.animeItem);
    if (mounted) {
      setState(() => _isFavorite = isFav);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final newStatus = await widget.store.toggleFavoriteFromItem(widget.animeItem);
      if (mounted) {
        setState(() => _isFavorite = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? '已添加到收藏' : '已取消收藏'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // 当从详情页面返回时，清空详情状态，避免显示占位页面
    widget.store.backToSearchResults();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Observer(
        builder: (context) {
          return CustomScrollView(
            slivers: [
              // 自定义AppBar
              SliverAppBar(
                expandedHeight: 0,
                floating: true,
                pinned: true,
                title: Text(
                  widget.animeItem.displayTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  // 收藏按钮
                  IconButton(
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? Colors.red : null,
                    ),
                    tooltip: _isFavorite ? '取消收藏' : '加入收藏',
                  ),
                ],
              ),

              // 详情头部信息
              SliverToBoxAdapter(
                child: AnimeDetailHeader(
                  animeItem: widget.animeItem,
                  store: widget.store,
                ),
              ),

              // 标签栏
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: '简介'),
                      Tab(text: '剧集'),
                    ],
                  ),
                ),
              ),

              // 标签页内容
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 简介标签页
                    AnimeDetailSummary(
                      animeItem: widget.animeItem,
                      store: widget.store,
                    ),
                    
                    // 剧集标签页
                    AnimeDetailEpisodes(
                      animeItem: widget.animeItem,
                      store: widget.store,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// TabBar的SliverPersistentHeaderDelegate
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverTabBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;

  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}