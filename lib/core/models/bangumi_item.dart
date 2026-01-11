/// Bangumi条目信息 - 基于Kazumi的BangumiItem简化版本
class BangumiItem {
  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final int airWeekday;
  final int rank;
  final Map<String, String> images;
  final List<String> tags;
  final List<String> alias;
  final double ratingScore;
  final int votes;
  final String info;

  BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.airWeekday,
    required this.rank,
    required this.images,
    required this.tags,
    required this.alias,
    required this.ratingScore,
    required this.votes,
    required this.info,
  });

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    // 解析别名
    List<String> parseBangumiAliases(Map<String, dynamic> jsonData) {
      if (jsonData.containsKey('infobox') && jsonData['infobox'] is List) {
        final List<dynamic> infobox = jsonData['infobox'];
        for (var item in infobox) {
          if (item is Map<String, dynamic> && item['key'] == '别名') {
            final dynamic value = item['value'];
            if (value is List) {
              return value
                  .map<String>((element) {
                    if (element is Map<String, dynamic> &&
                        element.containsKey('v')) {
                      return element['v'].toString();
                    }
                    return '';
                  })
                  .where((alias) => alias.isNotEmpty)
                  .toList();
            }
          }
        }
      }
      return [];
    }

    // 解析标签
    List<String> parseTagList(List<dynamic>? tagList) {
      if (tagList == null) return [];
      return tagList
          .map((tag) => tag is Map<String, dynamic> ? (tag['name'] ?? '') : '')
          .where((name) => name.isNotEmpty)
          .cast<String>()
          .toList();
    }

    List<String> bangumiAlias = parseBangumiAliases(json);
    List<String> tagList = parseTagList(json['tags']);

    return BangumiItem(
      id: json['id'] ?? 0,
      type: json['type'] ?? 2,
      name: json['name'] ?? '',
      nameCn: (json['name_cn'] ?? '') == ''
          ? (((json['nameCN'] ?? '') == '') ? json['name'] : json['nameCN'])
          : json['name_cn'],
      summary: json['summary'] ?? '',
      airDate: json['date'] ?? '',
      airWeekday: _dateStringToWeekday(json['date'] ?? '2000-11-11'),
      rank: json['rating']?['rank'] ?? 0,
      images: Map<String, String>.from(
        json['images'] ??
            {
              "large": json['image'] ?? '',
              "common": "",
              "medium": "",
              "small": "",
              "grid": ""
            },
      ),
      tags: tagList,
      alias: bangumiAlias,
      ratingScore: double.tryParse(
          (json['rating']?['score'] ?? 0.0).toDouble().toStringAsFixed(1)) ?? 0.0,
      votes: json['rating']?['total'] ?? 0,
      info: json['info'] ?? '',
    );
  }

  /// 将日期字符串转换为星期几
  static int _dateStringToWeekday(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return date.weekday;
    } catch (e) {
      return 1; // 默认星期一
    }
  }

  /// 获取最佳封面URL
  String get bestCoverUrl {
    if (images['large']?.isNotEmpty == true) return images['large']!;
    if (images['common']?.isNotEmpty == true) return images['common']!;
    if (images['medium']?.isNotEmpty == true) return images['medium']!;
    if (images['small']?.isNotEmpty == true) return images['small']!;
    return '';
  }

  /// 获取显示名称（优先中文名）
  String get displayName {
    return nameCn.isNotEmpty ? nameCn : name;
  }

  /// 是否有评分
  bool get hasRating {
    return ratingScore > 0 && votes > 0;
  }
}