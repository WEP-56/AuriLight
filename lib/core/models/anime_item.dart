import 'bangumi_item.dart';

/// 动漫搜索结果项
class AnimeItem {
  final String title;
  final String detailUrl;
  final String? coverUrl;
  final String ruleName;
  final String ruleKey;
  
  // Bangumi相关信息
  BangumiItem? bangumiInfo;
  bool bangumiSearched = false; // 是否已经搜索过Bangumi

  AnimeItem({
    required this.title,
    required this.detailUrl,
    this.coverUrl,
    required this.ruleName,
    required this.ruleKey,
    this.bangumiInfo,
    this.bangumiSearched = false,
  });

  /// 获取最佳封面URL（优先Bangumi，其次规则源）
  String? get bestCoverUrl {
    if (bangumiInfo?.bestCoverUrl.isNotEmpty == true) {
      return bangumiInfo!.bestCoverUrl;
    }
    return coverUrl;
  }

  /// 获取显示标题（优先Bangumi中文名，其次原标题）
  String get displayTitle {
    if (bangumiInfo?.displayName.isNotEmpty == true) {
      return bangumiInfo!.displayName;
    }
    return title;
  }

  /// 是否有Bangumi信息
  bool get hasBangumiInfo => bangumiInfo != null;

  /// 是否有评分信息
  bool get hasRating => bangumiInfo?.hasRating == true;

  /// 获取评分
  double get rating => bangumiInfo?.ratingScore ?? 0.0;

  /// 获取评分人数
  int get ratingCount => bangumiInfo?.votes ?? 0;

  /// 获取简介
  String get summary => bangumiInfo?.summary ?? '';

  /// 获取标签
  List<String> get tags => bangumiInfo?.tags ?? [];

  /// 复制并更新Bangumi信息
  AnimeItem copyWithBangumi(BangumiItem? bangumi, {bool searched = true}) {
    return AnimeItem(
      title: title,
      detailUrl: detailUrl,
      coverUrl: coverUrl,
      ruleName: ruleName,
      ruleKey: ruleKey,
      bangumiInfo: bangumi,
      bangumiSearched: searched,
    );
  }

  @override
  String toString() {
    return 'AnimeItem(title: $title, detailUrl: $detailUrl, coverUrl: $coverUrl, ruleName: $ruleName)';
  }
}

/// 动漫详情
class AnimeDetail {
  final String title;
  final String? coverUrl;
  final String? description;
  final String detailUrl;
  final List<AnimeEpisode> episodes;
  final String ruleName;
  final String ruleKey;

  AnimeDetail({
    required this.title,
    this.coverUrl,
    this.description,
    required this.detailUrl,
    required this.episodes,
    required this.ruleName,
    required this.ruleKey,
  });

  @override
  String toString() {
    return 'AnimeDetail(title: $title, episodes: ${episodes.length}, ruleName: $ruleName)';
  }
}

/// 动漫章节/集数
class AnimeEpisode {
  final String title;
  final String episodeUrl;
  final int episodeNumber;
  final int roadIndex; // 线路索引（用于多线路支持）

  AnimeEpisode({
    required this.title,
    required this.episodeUrl,
    required this.episodeNumber,
    this.roadIndex = 0,
  });

  @override
  String toString() {
    return 'AnimeEpisode(title: $title, episodeNumber: $episodeNumber, roadIndex: $roadIndex)';
  }
}