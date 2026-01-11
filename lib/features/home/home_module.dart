import 'package:flutter_modular/flutter_modular.dart';

import 'home_page.dart';
import 'home_store.dart';

/// 主页模块
class HomeModule extends Module {
  @override
  void binds(i) {
    i.addSingleton<HomeStore>(HomeStore.new);
  }

  @override
  void routes(r) {
    r.child('/', child: (context) => const HomePage());
  }
}