import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:get_it/get_it.dart';
import 'package:window_manager/window_manager.dart';

import 'home_store.dart';
import 'widgets/sidebar.dart';
import 'widgets/home_content.dart';
import '../anime/anime_page.dart';
import '../anime/anime_store.dart';
import '../anime/pages/anime_detail_page.dart';
import '../manga/pages/manga_page.dart';
import '../manga/manga_store.dart';
import '../live/live_module.dart';
import '../favorite/favorite_page.dart';
import '../../core/models/anime_item.dart';

/// 主页面 - 包含侧边栏和主内容区域
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HomeStore store = Modular.get<HomeStore>();

  @override
  void initState() {
    super.initState();
    store.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Observer(
          builder: (context) {
            if (!store.isInitialized) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在初始化...'),
                  ],
                ),
              );
            }

            if (store.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(store.error!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => store.initialize(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }

            return Row(
              children: [
                // 侧边栏
                SizedBox(
                  width: 280,
                  child: AppSidebar(store: store),
                ),
                
                // 分割线
                const VerticalDivider(width: 1),
                
                // 主内容区域 - 根据当前路由显示不同内容
                Expanded(
                  child: Column(
                    children: [
                      // 桌面平台显示窗口控制按钮
                      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                        _buildWindowTitleBar(),
                      // 主内容
                      Expanded(child: _buildMainContent()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Observer(
      builder: (context) {
        final currentRoute = store.currentRoute;
        
        switch (currentRoute) {
          case '/':
            return HomeContent(store: store);
          case '/favorites':
            return FavoritePage(
              onItemTap: (type, source, id, {String? title, String? cover}) async {
                // 根据类型导航到对应页面并打开详情
                if (type == 'manga') {
                  // 先导航到漫画页面
                  store.setCurrentRoute('/manga/$source');
                  // 然后加载详情
                  final mangaStore = GetIt.instance<MangaStore>();
                  mangaStore.selectRule(source);
                  await mangaStore.loadDetail(source, id);
                } else if (type == 'anime') {
                  // 先导航到动漫页面
                  store.setCurrentRoute('/anime/$source');
                  // 创建临时 AnimeItem 并打开详情页
                  final animeStore = Modular.get<AnimeStore>();
                  await animeStore.initialize(source);
                  final tempItem = _createTempAnimeItem(id, source, title: title, cover: cover);
                  // 使用 Navigator 打开详情页
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AnimeDetailPage(
                          animeItem: tempItem,
                          store: animeStore,
                        ),
                      ),
                    );
                  }
                } else if (type == 'live') {
                  store.setCurrentRoute('/live/$source');
                  // TODO: 直播间打开
                }
              },
            );
          case '/downloads':
            return _buildPlaceholderPage('下载', Icons.download);
          case '/history':
            return _buildPlaceholderPage('历史', Icons.history);
          case '/settings':
            return _buildPlaceholderPage('设置', Icons.settings);
          default:
            if (currentRoute.startsWith('/anime/')) {
              final ruleKey = currentRoute.replaceFirst('/anime/', '');
              return AnimePage(ruleKey: ruleKey);
            } else if (currentRoute.startsWith('/manga/')) {
              // 漫画页面路由 - 传递规则key参数
              final ruleKey = currentRoute.replaceFirst('/manga/', '');
              return MangaPage(ruleKey: ruleKey);
            } else if (currentRoute.startsWith('/live/')) {
              // 直播页面路由 - 传递平台ID参数
              final platformId = currentRoute.replaceFirst('/live/', '');
              return LiveModule(initialPlatformId: platformId.isEmpty ? null : platformId);
            }
            return HomeContent(store: store);
        }
      },
    );
  }

  Widget _buildPlaceholderPage(String title, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('$title功能开发中...'),
        ],
      ),
    );
  }

  /// 创建临时的 AnimeItem 用于从收藏加载详情
  AnimeItem _createTempAnimeItem(String detailUrl, String ruleKey, {String? title, String? cover}) {
    return AnimeItem(
      title: title ?? '', // 标题会从详情中获取
      detailUrl: detailUrl,
      coverUrl: cover,
      ruleName: ruleKey,
      ruleKey: ruleKey,
    );
  }

  /// 构建窗口标题栏（仅桌面平台）
  Widget _buildWindowTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 40,
        color: Colors.transparent,
        child: Row(
          children: [
            // 可拖动区域
            const Expanded(child: SizedBox()),
            // 窗口控制按钮
            const WindowButtons(),
          ],
        ),
      ),
    );
  }
}

/// 窗口控制按钮组件
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _updateMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _updateMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted && _isMaximized != isMaximized) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          icon: Icons.remove,
          onPressed: () => windowManager.minimize(),
          tooltip: '最小化',
        ),
        _WindowButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          onPressed: () async {
            if (_isMaximized) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          tooltip: _isMaximized ? '还原' : '最大化',
        ),
        _WindowButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          tooltip: '关闭',
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 40,
            color: _isHovering 
                ? (widget.isClose ? Colors.red : theme.colorScheme.surfaceContainerHighest)
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovering && widget.isClose
                  ? Colors.white
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}