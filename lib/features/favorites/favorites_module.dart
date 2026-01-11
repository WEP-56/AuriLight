import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// 收藏模块
class FavoritesModule extends Module {
  @override
  void binds(i) {
    // TODO: 添加收藏相关的服务和状态管理
  }

  @override
  void routes(r) {
    r.child('/', child: (context) => 
      const Center(child: Text('收藏页面开发中...')));
  }
}