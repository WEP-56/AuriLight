import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// 设置模块
class SettingsModule extends Module {
  @override
  void binds(i) {
    // TODO: 添加设置相关的服务和状态管理
  }

  @override
  void routes(r) {
    r.child('/', child: (context) => 
      const Center(child: Text('设置页面开发中...')));
  }
}