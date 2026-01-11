import 'package:hive_flutter/hive_flutter.dart';
import '../models/unified_rule.dart';
import '../models/favorite.dart';
import '../models/manga_item.dart';
import '../models/unified_models.dart';
import '../utils/logger.dart';

/// 应用存储管理器
class AppStorage {
  static bool _initialized = false;

  /// 初始化存储
  static Future<void> init() async {
    if (_initialized) return;

    try {
      // 注册Hive适配器
      _registerAdapters();

      // 打开必要的boxes
      await _openBoxes();

      _initialized = true;
      Logger.info('AppStorage initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize AppStorage: $e');
      rethrow;
    }
  }

  /// 注册Hive适配器
  static void _registerAdapters() {
    // 注册枚举适配器
    if (!Hive.isAdapterRegistered(30)) {
      Hive.registerAdapter(RuleTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(40)) {
      Hive.registerAdapter(FavoriteTypeAdapter());
    }

    // 注册模型适配器
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(UnifiedRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(SearchConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(DetailConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PlayConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(AccountConfigAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(FavoriteItemAdapter());
    }
    
    // 注册漫画相关适配器
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(MangaItemAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(MangaDetailAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(MangaChapterAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(UnifiedFavoriteAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(UnifiedHistoryAdapter());
    }
  }

  /// 打开必要的boxes
  static Future<void> _openBoxes() async {
    // 这些boxes会在各自的管理器中打开
    // 这里只是预检查
  }

  /// 清理所有数据
  static Future<void> clearAll() async {
    try {
      await Hive.deleteFromDisk();
      _initialized = false;
      Logger.info('All storage data cleared');
    } catch (e) {
      Logger.error('Failed to clear storage: $e');
      rethrow;
    }
  }

  /// 清理规则数据（用于修复兼容性问题）
  static Future<void> clearRulesData() async {
    try {
      if (Hive.isBoxOpen('unified_rules')) {
        final box = Hive.box<UnifiedRule>('unified_rules');
        await box.clear();
        Logger.info('Rules data cleared');
      }
    } catch (e) {
      Logger.error('Failed to clear rules data: $e');
      rethrow;
    }
  }

  /// 获取存储使用情况
  static Future<Map<String, int>> getStorageStats() async {
    final stats = <String, int>{};
    
    try {
      if (Hive.isBoxOpen('unified_rules')) {
        final rulesBox = Hive.box<UnifiedRule>('unified_rules');
        stats['rules'] = rulesBox.length;
      }
      
      if (Hive.isBoxOpen('favorites')) {
        final favoritesBox = Hive.box<FavoriteItem>('favorites');
        stats['favorites'] = favoritesBox.length;
      }
      
      // 可以添加更多统计信息
    } catch (e) {
      Logger.error('Failed to get storage stats: $e');
    }
    
    return stats;
  }
}

/// RuleType适配器
class RuleTypeAdapter extends TypeAdapter<RuleType> {
  @override
  final int typeId = 30;

  @override
  RuleType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RuleType.anime;
      case 1:
        return RuleType.manga;
      default:
        return RuleType.anime;
    }
  }

  @override
  void write(BinaryWriter writer, RuleType obj) {
    switch (obj) {
      case RuleType.anime:
        writer.writeByte(0);
        break;
      case RuleType.manga:
        writer.writeByte(1);
        break;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}

/// FavoriteType适配器
class FavoriteTypeAdapter extends TypeAdapter<FavoriteType> {
  @override
  final int typeId = 40;

  @override
  FavoriteType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return FavoriteType.anime;
      case 1:
        return FavoriteType.manga;
      case 2:
        return FavoriteType.localManga;
      default:
        return FavoriteType.anime;
    }
  }

  @override
  void write(BinaryWriter writer, FavoriteType obj) {
    switch (obj) {
      case FavoriteType.anime:
        writer.writeByte(0);
        break;
      case FavoriteType.manga:
        writer.writeByte(1);
        break;
      case FavoriteType.localManga:
        writer.writeByte(2);
        break;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  @override
  int get hashCode => typeId.hashCode;
}