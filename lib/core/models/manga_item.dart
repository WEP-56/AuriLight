import 'package:hive/hive.dart';

part 'manga_item.g.dart';

/// 漫画项目模型 - 搜索结果项
@HiveType(typeId: 5)
class MangaItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? subtitle;

  @HiveField(3)
  final String? cover;

  @HiveField(4)
  final List<String>? tags;

  @HiveField(5)
  final String? description;

  @HiveField(6)
  final String? language;

  @HiveField(7)
  final double? stars;

  @HiveField(8)
  final String ruleName;

  @HiveField(9)
  final String ruleKey;

  MangaItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.cover,
    this.tags,
    this.description,
    this.language,
    this.stars,
    required this.ruleName,
    required this.ruleKey,
  });

  /// 显示标题（优先使用title）
  String get displayTitle => title;

  /// 最佳封面URL
  String? get bestCoverUrl => cover;

  /// 是否有评分
  bool get hasRating => stars != null && stars! > 0;

  /// 从JS对象创建MangaItem
  factory MangaItem.fromJs(Map<String, dynamic> jsObject, String ruleName, String ruleKey) {
    return MangaItem(
      id: jsObject['id']?.toString() ?? '',
      title: jsObject['title']?.toString() ?? 'Unknown',
      subtitle: jsObject['subtitle']?.toString() ?? jsObject['subTitle']?.toString(),
      cover: jsObject['cover']?.toString(),
      tags: (jsObject['tags'] as List?)?.map((e) => e.toString()).toList(),
      description: jsObject['description']?.toString(),
      language: jsObject['language']?.toString(),
      stars: (jsObject['stars'] as num?)?.toDouble(),
      ruleName: ruleName,
      ruleKey: ruleKey,
    );
  }

  /// 转换为JS对象
  Map<String, dynamic> toJs() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'cover': cover,
      'tags': tags,
      'description': description,
      'language': language,
      'stars': stars,
    };
  }

  @override
  String toString() {
    return 'MangaItem(id: $id, title: $title, rule: $ruleKey)';
  }
}

/// 漫画详情模型
@HiveType(typeId: 6)
class MangaDetail extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? subtitle;

  @HiveField(3)
  final String? cover;

  @HiveField(4)
  final String? description;

  @HiveField(5)
  final Map<String, List<String>>? tags;

  @HiveField(6)
  final Map<String, String>? chapters;

  @HiveField(7)
  final bool? isFavorite;

  @HiveField(8)
  final List<String>? thumbnails;

  @HiveField(9)
  final List<MangaItem>? recommend;

  @HiveField(10)
  final int? commentCount;

  @HiveField(11)
  final String? uploader;

  @HiveField(12)
  final String? updateTime;

  @HiveField(13)
  final String? uploadTime;

  @HiveField(14)
  final String? url;

  @HiveField(15)
  final double? stars;

  @HiveField(16)
  final String ruleName;

  @HiveField(17)
  final String ruleKey;

  MangaDetail({
    required this.id,
    required this.title,
    this.subtitle,
    this.cover,
    this.description,
    this.tags,
    this.chapters,
    this.isFavorite,
    this.thumbnails,
    this.recommend,
    this.commentCount,
    this.uploader,
    this.updateTime,
    this.uploadTime,
    this.url,
    this.stars,
    required this.ruleName,
    required this.ruleKey,
  });

  /// 章节列表（按顺序）
  List<MangaChapter> get chapterList {
    if (chapters == null) return [];
    
    return chapters!.entries.map((entry) {
      return MangaChapter(
        id: entry.key,
        title: entry.value,
        mangaId: id,
        ruleKey: ruleKey,
      );
    }).toList();
  }

  /// 从JS对象创建MangaDetail
  factory MangaDetail.fromJs(Map<String, dynamic> jsObject, String mangaId, String ruleName, String ruleKey) {
    // 处理tags
    Map<String, List<String>>? tags;
    if (jsObject['tags'] != null) {
      final tagsData = jsObject['tags'];
      if (tagsData is Map) {
        tags = tagsData.map((key, value) {
          if (value is List) {
            return MapEntry(key.toString(), value.map((e) => e.toString()).toList());
          }
          return MapEntry(key.toString(), [value.toString()]);
        });
      }
    }

    // 处理chapters
    Map<String, String>? chapters;
    if (jsObject['chapters'] != null) {
      final chaptersData = jsObject['chapters'];
      if (chaptersData is Map) {
        chapters = chaptersData.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
    }

    // 处理recommend
    List<MangaItem>? recommend;
    if (jsObject['recommend'] != null && jsObject['recommend'] is List) {
      recommend = (jsObject['recommend'] as List)
          .map((item) => MangaItem.fromJs(item, ruleName, ruleKey))
          .toList();
    }

    return MangaDetail(
      id: mangaId,
      title: jsObject['title']?.toString() ?? 'Unknown',
      subtitle: jsObject['subtitle']?.toString() ?? jsObject['subTitle']?.toString(),
      cover: jsObject['cover']?.toString(),
      description: jsObject['description']?.toString(),
      tags: tags,
      chapters: chapters,
      isFavorite: jsObject['isFavorite'] as bool?,
      thumbnails: (jsObject['thumbnails'] as List?)?.map((e) => e.toString()).toList(),
      recommend: recommend,
      commentCount: jsObject['commentCount'] as int?,
      uploader: jsObject['uploader']?.toString(),
      updateTime: jsObject['updateTime']?.toString(),
      uploadTime: jsObject['uploadTime']?.toString(),
      url: jsObject['url']?.toString(),
      stars: (jsObject['stars'] as num?)?.toDouble(),
      ruleName: ruleName,
      ruleKey: ruleKey,
    );
  }

  @override
  String toString() {
    return 'MangaDetail(id: $id, title: $title, chapters: ${chapters?.length ?? 0})';
  }
}

/// 漫画章节模型
@HiveType(typeId: 7)
class MangaChapter extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String mangaId;

  @HiveField(3)
  final String ruleKey;

  @HiveField(4)
  final List<String>? images;

  @HiveField(5)
  final int? pageCount;

  MangaChapter({
    required this.id,
    required this.title,
    required this.mangaId,
    required this.ruleKey,
    this.images,
    this.pageCount,
  });

  /// 是否已加载图片
  bool get isLoaded => images != null && images!.isNotEmpty;

  @override
  String toString() {
    return 'MangaChapter(id: $id, title: $title, pages: ${images?.length ?? 0})';
  }
}