import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'anime_page.dart';

/// 动漫模块
class AnimeModule extends Module {
  @override
  void binds(i) {
    // AnimeStore 已在 AppModule 中注册为单例
  }

  @override
  void routes(r) {
    r.child('/', child: (context) => const AnimePage());
    // 动态路由 - 支持任意规则key
    r.child('/:ruleKey', child: (context) {
      final ruleKey = r.args.params['ruleKey'];
      return AnimePage(ruleKey: ruleKey);
    });
  }
}