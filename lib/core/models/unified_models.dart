import 'package:hive/hive.dart';

part 'unified_models.g.dart';

/// 统一收藏模型 - 支持动漫和漫画
@HiveType(typeId: 8)
class UnifiedFavorite extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String type; // 'anime' | 'manga'

  @HiveField(2)
  final String source; // 规则key

  @HiveField(3)
  final String title;

  @HiveField(4)
  final String? cover;

  @HiveField(5)
  final Map<String, dynamic> extra; // 额外信息

  @HiveField(6)
  final DateTime addedTime;

  UnifiedFavorite({
    required this.id,
    required this.type,
    required this.source,
    required this.title,
    this.cover,
    required this.extra,
    required this.addedTime,
  });

  /// 是否为动漫
  bool get isAnime => type == 'anime';

  /// 是否为漫画
  bool get isManga => type == 'manga';

  /// 显示的副标题
  String? get subtitle {
    if (isAnime) {
      return extra['episodeCount']?.toString();
    } else {
      return extra['chapterCount']?.toString();
    }
  }

  /// 从动漫项目创建收藏
  factory UnifiedFavorite.fromAnime({
    required String id,
    required String source,
    required String title,
    String? cover,
    int? episodeCount,
    String? status,
  }) {
    return UnifiedFavorite(
      id: id,
      type: 'anime',
      source: source,
      title: title,
      cover: cover,
      extra: {
        'episodeCount': episodeCount,
        'status': status,
      },
      addedTime: DateTime.now(),
    );
  }

  /// 从漫画项目创建收藏
  factory UnifiedFavorite.fromManga({
    required String id,
    required String source,
    required String title,
    String? cover,
    int? chapterCount,
    String? author,
    List<String>? tags,
  }) {
    return UnifiedFavorite(
      id: id,
      type: 'manga',
      source: source,
      title: title,
      cover: cover,
      extra: {
        'chapterCount': chapterCount,
        'author': author,
        'tags': tags,
      },
      addedTime: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'UnifiedFavorite(type: $type, title: $title, source: $source)';
  }
}

/// 统一历史记录模型 - 支持动漫和漫画
@HiveType(typeId: 9)
class UnifiedHistory extends HiveObject {
  @HiveField(0)
  final String type; // 'anime' | 'manga'

  @HiveField(1)
  final String contentId; // 动漫ID或漫画ID

  @HiveField(2)
  final String source; // 规则key

  @HiveField(3)
  final String title;

  @HiveField(4)
  final String? cover;

  @HiveField(5)
  final DateTime lastAccess;

  @HiveField(6)
  final Map<String, dynamic> progress; // 进度信息

  UnifiedHistory({
    required this.type,
    required this.contentId,
    required this.source,
    required this.title,
    this.cover,
    required this.lastAccess,
    required this.progress,
  });

  /// 是否为动漫
  bool get isAnime => type == 'anime';

  /// 是否为漫画
  bool get isManga => type == 'manga';

  /// 进度描述
  String get progressDescription {
    if (isAnime) {
      final episode = progress['episode']?.toString() ?? '未知';
      final position = progress['position'] as int?;
      if (position != null) {
        final minutes = (position / 60000).round();
        return '第$episode集 ${minutes}分钟';
      }
      return '第$episode集';
    } else {
      final chapter = progress['chapter']?.toString() ?? '未知';
      final page = progress['page'] as int?;
      if (page != null) {
        return '$chapter 第${page + 1}页';
      }
      return chapter;
    }
  }

  /// 从动漫观看记录创建历史
  factory UnifiedHistory.fromAnime({
    required String animeId,
    required String source,
    required String title,
    String? cover,
    required String episode,
    int? position, // 播放位置（毫秒）
  }) {
    return UnifiedHistory(
      type: 'anime',
      contentId: animeId,
      source: source,
      title: title,
      cover: cover,
      lastAccess: DateTime.now(),
      progress: {
        'episode': episode,
        'position': position,
      },
    );
  }

  /// 从漫画阅读记录创建历史
  factory UnifiedHistory.fromManga({
    required String mangaId,
    required String source,
    required String title,
    String? cover,
    required String chapter,
    int? page, // 页码（从0开始）
    double? scrollOffset, // 滚动偏移
  }) {
    return UnifiedHistory(
      type: 'manga',
      contentId: mangaId,
      source: source,
      title: title,
      cover: cover,
      lastAccess: DateTime.now(),
      progress: {
        'chapter': chapter,
        'page': page,
        'scrollOffset': scrollOffset,
      },
    );
  }

  /// 更新进度
  UnifiedHistory updateProgress(Map<String, dynamic> newProgress) {
    return UnifiedHistory(
      type: type,
      contentId: contentId,
      source: source,
      title: title,
      cover: cover,
      lastAccess: DateTime.now(),
      progress: {...progress, ...newProgress},
    );
  }

  @override
  String toString() {
    return 'UnifiedHistory(type: $type, title: $title, progress: $progressDescription)';
  }
}