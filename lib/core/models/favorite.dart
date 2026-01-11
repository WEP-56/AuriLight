import 'package:hive/hive.dart';

part 'favorite.g.dart';

/// 收藏项类型
@HiveType(typeId: 20)
enum FavoriteType {
  @HiveField(0)
  anime,
  @HiveField(1)
  manga,
  @HiveField(2)
  localManga, // 本地漫画
}

/// 统一收藏项
@HiveType(typeId: 21)
class FavoriteItem extends HiveObject {
  @HiveField(0)
  String id; // 内容ID
  
  @HiveField(1)
  FavoriteType type; // 类型
  
  @HiveField(2)
  String title; // 标题
  
  @HiveField(3)
  String? cover; // 封面URL或路径
  
  @HiveField(4)
  String source; // 来源URL
  
  @HiveField(5)
  String ruleName; // 规则名称
  
  @HiveField(6)
  DateTime addedAt; // 添加时间
  
  @HiveField(7)
  Map<String, dynamic>? metadata; // 额外元数据
  
  @HiveField(8)
  String? description; // 描述
  
  @HiveField(9)
  List<String>? tags; // 标签

  FavoriteItem({
    required this.id,
    required this.type,
    required this.title,
    this.cover,
    required this.source,
    required this.ruleName,
    required this.addedAt,
    this.metadata,
    this.description,
    this.tags,
  });

  /// 创建动漫收藏项
  factory FavoriteItem.anime({
    required String id,
    required String title,
    String? cover,
    required String source,
    required String ruleName,
    String? description,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return FavoriteItem(
      id: id,
      type: FavoriteType.anime,
      title: title,
      cover: cover,
      source: source,
      ruleName: ruleName,
      addedAt: DateTime.now(),
      description: description,
      tags: tags,
      metadata: metadata,
    );
  }

  /// 创建漫画收藏项
  factory FavoriteItem.manga({
    required String id,
    required String title,
    String? cover,
    required String source,
    required String ruleName,
    String? description,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return FavoriteItem(
      id: id,
      type: FavoriteType.manga,
      title: title,
      cover: cover,
      source: source,
      ruleName: ruleName,
      addedAt: DateTime.now(),
      description: description,
      tags: tags,
      metadata: metadata,
    );
  }

  /// 创建本地漫画收藏项
  factory FavoriteItem.localManga({
    required String id,
    required String title,
    String? cover,
    required String source, // 本地路径
    String? description,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) {
    return FavoriteItem(
      id: id,
      type: FavoriteType.localManga,
      title: title,
      cover: cover,
      source: source,
      ruleName: 'local',
      addedAt: DateTime.now(),
      description: description,
      tags: tags,
      metadata: metadata,
    );
  }

  /// 获取唯一键
  String get uniqueKey => '${type.name}_${ruleName}_$id';

  /// 是否为本地内容
  bool get isLocal => type == FavoriteType.localManga;

  /// 更新元数据
  void updateMetadata(Map<String, dynamic> newMetadata) {
    metadata = {...?metadata, ...newMetadata};
    save();
  }

  /// 更新封面
  void updateCover(String newCover) {
    cover = newCover;
    save();
  }

  @override
  String toString() {
    return 'FavoriteItem(id: $id, type: $type, title: $title, ruleName: $ruleName)';
  }
}