/// Live streaming manager for KazuVera2D
/// Uses simple_live_core library for platform implementations
library;

import 'package:simple_live_core/simple_live_core.dart';

class LiveManager {
  static final LiveManager _instance = LiveManager._internal();
  factory LiveManager() => _instance;
  LiveManager._internal();

  final Map<String, LiveSite> _sites = {};
  String? _currentSiteId;

  /// Initialize all live streaming platforms
  Future<void> initialize() async {
    _sites.clear();
    
    // Initialize all platforms using simple_live_core
    _sites['bilibili'] = BiliBiliSite();
    _sites['douyu'] = DouyuSite();
    _sites['huya'] = HuyaSite();
    _sites['douyin'] = DouyinSite();
  }

  /// Get all available live sites
  List<LiveSite> get allSites => _sites.values.toList();

  /// Get site by ID
  LiveSite? getSite(String siteId) => _sites[siteId];

  /// Get current selected site
  LiveSite? get currentSite => _currentSiteId != null ? _sites[_currentSiteId] : null;

  /// Get current site ID
  String? get currentSiteId => _currentSiteId;

  /// Set current site
  void setCurrentSite(String siteId) {
    if (_sites.containsKey(siteId)) {
      _currentSiteId = siteId;
    }
  }

  /// Search rooms on current platform
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.searchRooms(keyword, page: page);
  }

  /// Get recommend rooms from current platform
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getRecommendRooms(page: page);
  }

  /// Get category rooms from current platform
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category, {int page = 1}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getCategoryRooms(category, page: page);
  }

  /// Get room detail from current platform
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getRoomDetail(roomId: roomId);
  }

  /// Get categories from current platform
  Future<List<LiveCategory>> getCategories() async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getCategores();
  }

  /// Get live status from current platform
  Future<bool> getLiveStatus({required String roomId}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getLiveStatus(roomId: roomId);
  }

  /// Get play qualities from current platform
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoomDetail detail}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getPlayQualites(detail: detail);
  }

  /// Get play URLs from current platform
  Future<LivePlayUrl> getPlayUrls({required LiveRoomDetail detail, required LivePlayQuality quality}) async {
    if (currentSite == null) {
      throw Exception('未选择直播平台');
    }
    return await currentSite!.getPlayUrls(detail: detail, quality: quality);
  }

  /// Get danmaku instance for current platform
  LiveDanmaku? getDanmaku() {
    return currentSite?.getDanmaku();
  }

  /// Set cookie for platforms that support login
  Future<void> setCookie(String siteId, String cookie) async {
    final site = _sites[siteId];
    if (site == null) return;
    
    if (site is BiliBiliSite) {
      site.cookie = cookie;
      // Parse user ID from cookie
      final match = RegExp(r'(?:^|;\s*)DedeUserID=(\d+)').firstMatch(cookie);
      if (match != null) {
        site.userId = int.tryParse(match.group(1) ?? '0') ?? 0;
      }
    } else if (site is DouyinSite) {
      site.cookie = cookie;
    }
  }

  /// Check if site supports login
  bool supportsCookieLogin(String siteId) {
    final site = _sites[siteId];
    return site is BiliBiliSite || site is DouyinSite;
  }

  /// Check if site is logged in
  bool isLoggedIn(String siteId) {
    final site = _sites[siteId];
    if (site is BiliBiliSite) {
      return site.cookie.trim().isNotEmpty;
    } else if (site is DouyinSite) {
      return site.cookie.trim().isNotEmpty;
    }
    return false;
  }
}
