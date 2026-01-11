import 'package:hive_flutter/hive_flutter.dart';
import '../models/unified_models.dart';
import '../utils/logger.dart';

/// 收藏类型
enum FavoriteCategory {
  all,
  live,
  anime,
  manga,
}

/// 收藏服务 - 管理所有类型的收藏
class FavoriteService {
  static final FavoriteService _instance = FavoriteService._internal();
  factory FavoriteService() => _instance;
  FavoriteService._internal();

  static const String _boxName = 'unified_favorites';
  Box<UnifiedFavorite>? _box;

  /// 初始化服务
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<UnifiedFavorite>(_boxName);
    Logger.info('FavoriteService initialized with ${_box!.length} favorites');
  }

  /// 确保已初始化
  Future<Box<UnifiedFavorite>> _ensureBox() async {
    if (_box == null || !_box!.isOpen) {
      await init();
    }
    return _box!;
  }

  /// 生成唯一键
  String _generateKey(String type, String source, String id) {
    return '${type}_${source}_$id';
  }

  /// 添加收藏
  Future<bool> addFavorite(UnifiedFavorite favorite) async {
    try {
      final box = await _ensureBox();
      final key = _generateKey(favorite.type, favorite.source, favorite.id);
      
      if (box.containsKey(key)) {
        Logger.info('Favorite already exists: $key');
        return false;
      }
      
      await box.put(key, favorite);
      Logger.info('Added favorite: ${favorite.title}');
      return true;
    } catch (e) {
      Logger.error('Failed to add favorite: $e');
      return false;
    }
  }

  /// 移除收藏
  Future<bool> removeFavorite(String type, String source, String id) async {
    try {
      final box = await _ensureBox();
      final key = _generateKey(type, source, id);
      
      if (!box.containsKey(key)) {
        Logger.info('Favorite not found: $key');
        return false;
      }
      
      await box.delete(key);
      Logger.info('Removed favorite: $key');
      return true;
    } catch (e) {
      Logger.error('Failed to remove favorite: $e');
      return false;
    }
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String type, String source, String id) async {
    try {
      final box = await _ensureBox();
      final key = _generateKey(type, source, id);
      return box.containsKey(key);
    } catch (e) {
      Logger.error('Failed to check favorite: $e');
      return false;
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(UnifiedFavorite favorite) async {
    final isFav = await isFavorite(favorite.type, favorite.source, favorite.id);
    if (isFav) {
      return await removeFavorite(favorite.type, favorite.source, favorite.id);
    } else {
      return await addFavorite(favorite);
    }
  }

  /// 获取所有收藏
  Future<List<UnifiedFavorite>> getAllFavorites() async {
    try {
      final box = await _ensureBox();
      return box.values.toList()
        ..sort((a, b) => b.addedTime.compareTo(a.addedTime));
    } catch (e) {
      Logger.error('Failed to get all favorites: $e');
      return [];
    }
  }

  /// 按类型获取收藏
  Future<List<UnifiedFavorite>> getFavoritesByType(String type) async {
    try {
      final box = await _ensureBox();
      return box.values
          .where((f) => f.type == type)
          .toList()
        ..sort((a, b) => b.addedTime.compareTo(a.addedTime));
    } catch (e) {
      Logger.error('Failed to get favorites by type: $e');
      return [];
    }
  }

  /// 获取直播收藏
  Future<List<UnifiedFavorite>> getLiveFavorites() async {
    return getFavoritesByType('live');
  }

  /// 获取动漫收藏
  Future<List<UnifiedFavorite>> getAnimeFavorites() async {
    return getFavoritesByType('anime');
  }

  /// 获取漫画收藏
  Future<List<UnifiedFavorite>> getMangaFavorites() async {
    return getFavoritesByType('manga');
  }

  /// 获取收藏数量
  Future<Map<String, int>> getFavoriteCounts() async {
    try {
      final box = await _ensureBox();
      final counts = <String, int>{
        'all': box.length,
        'live': 0,
        'anime': 0,
        'manga': 0,
      };
      
      for (final favorite in box.values) {
        counts[favorite.type] = (counts[favorite.type] ?? 0) + 1;
      }
      
      return counts;
    } catch (e) {
      Logger.error('Failed to get favorite counts: $e');
      return {'all': 0, 'live': 0, 'anime': 0, 'manga': 0};
    }
  }

  /// 清空所有收藏
  Future<void> clearAll() async {
    try {
      final box = await _ensureBox();
      await box.clear();
      Logger.info('Cleared all favorites');
    } catch (e) {
      Logger.error('Failed to clear favorites: $e');
    }
  }
}
