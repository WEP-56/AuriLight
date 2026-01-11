import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../home_store.dart';

/// 主内容区域
class MainContent extends StatelessWidget {
  final HomeStore store;

  const MainContent({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        // 使用 RouterOutlet 来显示路由内容
        return const RouterOutlet();
      },
    );
  }
}