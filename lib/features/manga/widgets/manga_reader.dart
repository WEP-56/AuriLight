import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/services/manga_image_provider.dart';

/// 阅读模式
enum ReaderMode {
  /// 左右翻页（默认）
  horizontal,
  /// 上下滚动
  vertical,
}

/// 漫画阅读器组件
class MangaReader extends StatefulWidget {
  final List<String> images;
  final bool isLoading;
  final VoidCallback onBack;
  final Function(int) onPageChanged;
  final String? ruleKey;
  final String? chapterId; // 章节ID，用于JM图片解密
  final bool hasAccount;
  final Future<bool> Function(String username, String password)? onLogin;
  final Future<bool> Function()? onReLogin;
  final Future<void> Function()? onLogout;
  final Map<String, String>? headers;
  final String? referer;
  final List<String>? cdnFallbacks;
  final bool forceWebView;

  const MangaReader({
    super.key,
    required this.images,
    required this.isLoading,
    required this.onBack,
    required this.onPageChanged,
    this.ruleKey,
    this.chapterId,
    this.hasAccount = false,
    this.onLogin,
    this.onReLogin,
    this.onLogout,
    this.headers,
    this.referer,
    this.cdnFallbacks,
    this.forceWebView = false,
  });

  @override
  State<MangaReader> createState() => _MangaReaderState();
}

class _MangaReaderState extends State<MangaReader> {
  late PageController _pageController;
  late ScrollController _scrollController;
  int _currentPage = 0;
  bool _showControls = true;
  bool _isFullscreen = false;
  ReaderMode _readerMode = ReaderMode.horizontal;
  
  // 预加载配置
  static const int _preloadCount = 5;
  final Set<int> _preloadedIndices = {};
  
  // 双击缩放相关
  final Map<int, PhotoViewController> _photoControllers = {};
  
  // 键盘焦点
  final FocusNode _focusNode = FocusNode();
  
  // 滚动模式下的当前页面追踪
  final Map<int, GlobalKey> _imageKeys = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheImages(_currentPage);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    for (final controller in _photoControllers.values) {
      controller.dispose();
    }
    // 退出时恢复非全屏
    if (_isFullscreen) {
      _exitFullscreen();
    }
    super.dispose();
  }

  // 滚动监听，更新当前页码
  void _onScrollChanged() {
    if (_readerMode != ReaderMode.vertical) return;
    // 简单估算当前页面（基于滚动位置）
    // 实际实现可以更精确
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _goToPage(int page) {
    if (page < 0 || page >= widget.images.length) return;
    
    if (_readerMode == ReaderMode.horizontal) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 垂直滚动模式：滚动到对应图片
      final key = _imageKeys[page];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _nextPage() {
    if (_currentPage < widget.images.length - 1) {
      _goToPage(_currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1);
    }
  }

  // 预加载图片
  void _precacheImages(int centerIndex) {
    if (!mounted) return;
    
    // 解析章节ID为整数（用于JM解密）
    final epId = widget.chapterId != null ? int.tryParse(widget.chapterId!) : null;
    
    for (int i = -1; i <= _preloadCount; i++) {
      final target = centerIndex + i;
      if (target < 0 || target >= widget.images.length) continue;
      if (_preloadedIndices.contains(target)) continue;
      
      _preloadedIndices.add(target);
      precacheImage(
        MangaImageProvider(
          sourceKey: widget.ruleKey ?? 'unknown',
          imageUrl: widget.images[target],
          headers: widget.headers,
          referer: widget.referer,
          cdnFallbacks: widget.cdnFallbacks,
          forceWebView: widget.forceWebView,
          epId: epId,
        ),
        context,
      );
    }
  }

  // 全屏切换
  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    } else {
      await _enterFullscreen();
    }
  }

  Future<void> _enterFullscreen() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(true);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() {
      _isFullscreen = true;
    });
  }

  Future<void> _exitFullscreen() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.setFullScreen(false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (mounted) {
      setState(() {
        _isFullscreen = false;
      });
    }
  }

  // 切换阅读模式
  void _toggleReaderMode() {
    setState(() {
      _readerMode = _readerMode == ReaderMode.horizontal 
          ? ReaderMode.vertical 
          : ReaderMode.horizontal;
    });
  }

  // 键盘事件处理
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _nextPage();
        break;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _prevPage();
        break;
      case LogicalKeyboardKey.home:
        _goToPage(0);
        break;
      case LogicalKeyboardKey.end:
        _goToPage(widget.images.length - 1);
        break;
      case LogicalKeyboardKey.escape:
        if (_isFullscreen) {
          _exitFullscreen();
        } else {
          widget.onBack();
        }
        break;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        break;
    }
  }

  // 鼠标滚轮处理
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      if (_readerMode == ReaderMode.horizontal) {
        // 水平模式：滚轮翻页
        if (event.scrollDelta.dy > 0) {
          _nextPage();
        } else if (event.scrollDelta.dy < 0) {
          _prevPage();
        }
      }
      // 垂直模式：滚轮由ScrollController自动处理
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (widget.images.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
          ),
        ),
        body: const Center(
          child: Text('没有图片', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 图片查看器
              _readerMode == ReaderMode.horizontal
                  ? _buildHorizontalReader()
                  : _buildVerticalReader(),
              
              // 顶部控制栏
              if (_showControls)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(context),
                ),
              
              // 底部控制栏
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(context),
                ),
              
              // 页面指示器
              if (_showControls)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  right: 16,
                  child: _buildPageIndicator(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 水平翻页阅读器
  Widget _buildHorizontalReader() {
    // 解析章节ID为整数（用于JM解密）
    final epId = widget.chapterId != null ? int.tryParse(widget.chapterId!) : null;
    
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (BuildContext context, int index) {
        // 为每个页面创建控制器
        _photoControllers[index] ??= PhotoViewController();
        
        return PhotoViewGalleryPageOptions(
          imageProvider: MangaImageProvider(
            sourceKey: widget.ruleKey ?? 'unknown',
            imageUrl: widget.images[index],
            headers: widget.headers,
            referer: widget.referer,
            cdnFallbacks: widget.cdnFallbacks,
            forceWebView: widget.forceWebView,
            epId: epId,
          ),
          controller: _photoControllers[index],
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 3.0,
          filterQuality: FilterQuality.medium,
          onTapUp: (context, details, value) {
            // 单击切换控制栏
            _toggleControls();
          },
          // 双击缩放由 PhotoView 内置处理
          onScaleEnd: (context, details, value) {
            // 缩放结束时可以做一些处理
          },
          errorBuilder: (context, error, stackTrace, retry) {
            return _buildErrorWidget(context, retry);
          },
        );
      },
      itemCount: widget.images.length,
      loadingBuilder: (context, event) => _buildLoadingWidget(context, event),
      pageController: _pageController,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
        _precacheImages(index);
        widget.onPageChanged(index);
        
        // 清理远离当前页面的控制器
        _cleanupControllers(index);
      },
    );
  }

  // 垂直滚动阅读器
  Widget _buildVerticalReader() {
    // 解析章节ID为整数（用于JM解密）
    final epId = widget.chapterId != null ? int.tryParse(widget.chapterId!) : null;
    
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.images.length,
      itemBuilder: (context, index) {
        _imageKeys[index] ??= GlobalKey();
        
        return Container(
          key: _imageKeys[index],
          color: Colors.black,
          child: GestureDetector(
            onDoubleTap: () => _handleDoubleTapVertical(index),
            child: Image(
              image: MangaImageProvider(
                sourceKey: widget.ruleKey ?? 'unknown',
                imageUrl: widget.images[index],
                headers: widget.headers,
                referer: widget.referer,
                cdnFallbacks: widget.cdnFallbacks,
                forceWebView: widget.forceWebView,
                epId: epId,
              ),
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 300,
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 300,
                  color: Colors.black,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 48, color: Colors.white54),
                        SizedBox(height: 8),
                        Text('图片加载失败', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _handleDoubleTapVertical(int index) {
    // 垂直模式下双击暂不支持缩放（需要更复杂的实现）
    // 可以考虑打开单独的图片查看器
  }

  // 清理远离当前页面的控制器以节省内存
  void _cleanupControllers(int currentIndex) {
    final keysToRemove = <int>[];
    for (final key in _photoControllers.keys) {
      if ((key - currentIndex).abs() > 3) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _photoControllers[key]?.dispose();
      _photoControllers.remove(key);
    }
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: widget.onBack,
            tooltip: '返回',
          ),
          const Spacer(),
          // 阅读模式切换
          IconButton(
            icon: Icon(
              _readerMode == ReaderMode.horizontal 
                  ? Icons.swap_vert 
                  : Icons.swap_horiz,
              color: Colors.white,
            ),
            onPressed: _toggleReaderMode,
            tooltip: _readerMode == ReaderMode.horizontal ? '切换为上下滚动' : '切换为左右翻页',
          ),
          // 全屏按钮
          IconButton(
            icon: Icon(
              _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: _toggleFullscreen,
            tooltip: _isFullscreen ? '退出全屏' : '全屏',
          ),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => _showReaderSettings(context),
            tooltip: '设置',
          ),
          if (widget.hasAccount)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'login') _showLoginDialog();
                else if (value == 'relogin') _doReLogin();
                else if (value == 'logout') _doLogout();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'login', child: Text('登录')),
                PopupMenuItem(value: 'relogin', child: Text('重登')),
                PopupMenuItem(value: 'logout', child: Text('退出登录')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.navigate_before, color: Colors.white),
            onPressed: _currentPage > 0 ? _prevPage : null,
          ),
          Expanded(
            child: Slider(
              value: _currentPage.toDouble(),
              min: 0,
              max: (widget.images.length - 1).toDouble().clamp(0, double.infinity),
              divisions: widget.images.length > 1 ? widget.images.length - 1 : null,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.3),
              onChanged: (value) => _goToPage(value.round()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.navigate_next, color: Colors.white),
            onPressed: _currentPage < widget.images.length - 1 ? _nextPage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${_currentPage + 1} / ${widget.images.length}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLoadingWidget(BuildContext context, ImageChunkEvent? event) {
    return Container(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          value: event != null && event.expectedTotalBytes != null
              ? event.cumulativeBytesLoaded / event.expectedTotalBytes!
              : null,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, VoidCallback retry) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('图片加载失败', style: TextStyle(color: Colors.white54, fontSize: 16)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh, color: Colors.white70),
              label: const Text('重试', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  void _showReaderSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        
                        // 阅读模式
                        ListTile(
                          leading: const Icon(Icons.view_carousel),
                          title: const Text('阅读模式'),
                          subtitle: Text(_readerMode == ReaderMode.horizontal 
                              ? '左右翻页' : '上下滚动'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            _toggleReaderMode();
                            setModalState(() {});
                          },
                        ),
                        
                        // 全屏
                        SwitchListTile(
                          secondary: const Icon(Icons.fullscreen),
                          title: const Text('全屏模式'),
                          value: _isFullscreen,
                          onChanged: (value) {
                            _toggleFullscreen();
                            setModalState(() {});
                          },
                        ),
                        
                        const Divider(),
                        
                        // 快捷键提示
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('快捷键', style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              Text('← → / ↑ ↓ : 翻页', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('Space / PageDown : 下一页', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('F : 全屏切换', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('Esc : 退出全屏/返回', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text('滚轮 : 翻页', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 登录相关方法
  Future<void> _showLoginDialog() async {
    if (widget.onLogin == null) return;
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: '账号'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('登录'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await widget.onLogin!(username, password);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '登录成功' : '登录失败')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录出错: $e')),
      );
    }
  }

  Future<void> _doReLogin() async {
    if (widget.onReLogin == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final ok = await widget.onReLogin!();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '重登成功' : '重登失败')),
    );
  }

  Future<void> _doLogout() async {
    if (widget.onLogout == null) return;
    await widget.onLogout!();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }
}
