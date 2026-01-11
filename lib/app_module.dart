import 'package:flutter_modular/flutter_modular.dart';

import 'core/rule_engine/rule_manager.dart';
import 'features/home/home_module.dart';
import 'features/anime/anime_module.dart';
import 'features/anime/anime_store.dart';
import 'features/manga/manga_module.dart';
import 'features/live/live_module_router.dart';
import 'features/favorites/favorites_module.dart';
import 'features/settings/settings_module.dart';

/// 应用主模块
class AppModule extends Module {
  @override
  void binds(i) {
    // 注册单例服务
    i.addSingleton<RuleManager>(() => RuleManager());
    i.addSingleton<AnimeStore>(() => AnimeStore());
  }

  @override
  void routes(r) {
    // 主页路由
    r.module('/', module: HomeModule());
    
    // 动漫模块路由
    r.module('/anime', module: AnimeModule());
    
    // 漫画模块路由
    r.module('/manga', module: MangaModule());
    
    // 直播模块路由
    r.module('/live', module: LiveModuleRouter());
    
    // 收藏模块路由
    r.module('/favorites', module: FavoritesModule());
    
    // 设置模块路由
    r.module('/settings', module: SettingsModule());
  }
}