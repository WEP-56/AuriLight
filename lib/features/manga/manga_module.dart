import 'package:flutter_modular/flutter_modular.dart';
import 'package:get_it/get_it.dart';

import 'manga_store.dart';
import 'pages/manga_page.dart';

/// 漫画模块 - 处理漫画相关的路由和依赖注入
class MangaModule extends Module {
  @override
  void binds(Injector i) {
    // 注册MangaStore为单例
    i.addSingleton<MangaStore>(() => MangaStore());
  }

  @override
  void routes(RouteManager r) {
    // 漫画主页面
    r.child('/', child: (context) => const MangaPage());
  }
}

/// 漫画模块初始化器
class MangaModuleInitializer {
  static Future<void> initialize() async {
    // 注册到GetIt（用于非Modular的地方访问）
    if (!GetIt.instance.isRegistered<MangaStore>()) {
      GetIt.instance.registerSingleton<MangaStore>(MangaStore());
    }
  }
}