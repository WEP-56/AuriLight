import 'package:flutter/material.dart';
import '../../core/models/unified_models.dart';
import '../../core/services/favorite_service.dart';
import '../../core/services/manga_image_provider.dart';

/// 收藏页面
class FavoritePage extends StatefulWidget {
  final Function(String type, String source, String id, {String? title, String? cover})? onItemTap;

  const FavoritePage({
    super.key,
    this.onItemTap,
  });

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FavoriteService _favoriteService = FavoriteService();
  
  List<UnifiedFavorite> _allFavorites = [];
  List<UnifiedFavorite> _liveFavorites = [];
  List<UnifiedFavorite> _animeFavorites = [];
  List<UnifiedFavorite> _mangaFavorites = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadFavorites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    
    await _favoriteService.init();
    
    final all = await _favoriteService.getAllFavorites();
    final live = await _favoriteService.getLiveFavorites();
    final anime = await _favoriteService.getAnimeFavorites();
    final manga = await _favoriteService.getMangaFavorites();
    
    if (mounted) {
      setState(() {
        _allFavorites = all;
        _liveFavorites = live;
        _animeFavorites = anime;
        _mangaFavorites = manga;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFavorite(UnifiedFavorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定要取消收藏 "${favorite.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _favoriteService.removeFavorite(
        favorite.type,
        favorite.source,
        favorite.id,
      );
      await _loadFavorites();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏 "${favorite.title}"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab 栏
        Container(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: '全部 (${_allFavorites.length})'),
              Tab(text: '直播 (${_liveFavorites.length})'),
              Tab(text: '动画 (${_animeFavorites.length})'),
              Tab(text: '漫画 (${_mangaFavorites.length})'),
            ],
          ),
        ),
        
        // 内容区域
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFavoriteGrid(_allFavorites),
                    _buildFavoriteGrid(_liveFavorites),
                    _buildFavoriteGrid(_animeFavorites),
                    _buildFavoriteGrid(_mangaFavorites),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFavoriteGrid(List<UnifiedFavorite> favorites) {
    if (favorites.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: favorites.length,
        itemBuilder: (context, index) {
          return _buildFavoriteCard(favorites[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无收藏',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '浏览内容时点击收藏按钮添加',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(UnifiedFavorite favorite) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onItemTap?.call(
          favorite.type,
          favorite.source,
          favorite.id,
          title: favorite.title,
          cover: favorite.cover,
        ),
        onLongPress: () => _removeFavorite(favorite),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(favorite),
                  // 类型标签
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _buildTypeChip(favorite.type),
                  ),
                ],
              ),
            ),
            
            // 标题和信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favorite.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    favorite.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(UnifiedFavorite favorite) {
    if (favorite.cover == null || favorite.cover!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          _getTypeIcon(favorite.type),
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    // 漫画使用 MangaImageProvider
    if (favorite.type == 'manga') {
      return Image(
        image: MangaImageProvider(
          sourceKey: favorite.source,
          imageUrl: favorite.cover!,
        ),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image),
          );
        },
      );
    }

    // 其他类型使用普通网络图片
    return Image.network(
      favorite.cover!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }

  Widget _buildTypeChip(String type) {
    final color = _getTypeColor(type);
    final icon = _getTypeIcon(type);
    final label = _getTypeLabel(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'live':
        return Colors.red;
      case 'anime':
        return Colors.blue;
      case 'manga':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'live':
        return Icons.live_tv;
      case 'anime':
        return Icons.play_circle;
      case 'manga':
        return Icons.book;
      default:
        return Icons.star;
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'live':
        return '直播';
      case 'anime':
        return '动画';
      case 'manga':
        return '漫画';
      default:
        return '未知';
    }
  }
}
