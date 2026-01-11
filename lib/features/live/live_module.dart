/// Live streaming module for KazuVera2D
/// Handles live streaming functionality
library;

import 'package:flutter/material.dart';
import '../../core/services/live_manager.dart';
import 'pages/live_page.dart';

class LiveModule extends StatefulWidget {
  final String? initialPlatformId;

  const LiveModule({
    super.key,
    this.initialPlatformId,
  });

  @override
  State<LiveModule> createState() => _LiveModuleState();
}

class _LiveModuleState extends State<LiveModule> {
  String? _currentPlatformId;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeLiveModule();
  }

  @override
  void didUpdateWidget(LiveModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 initialPlatformId 变化时，更新当前平台
    if (oldWidget.initialPlatformId != widget.initialPlatformId && 
        widget.initialPlatformId != null &&
        widget.initialPlatformId != _currentPlatformId) {
      _switchPlatform(widget.initialPlatformId!);
    }
  }

  Future<void> _initializeLiveModule() async {
    try {
      // 初始化直播管理器
      await LiveManager().initialize();
      
      // 设置初始平台
      String? platformId = widget.initialPlatformId;
      if (platformId == null || platformId.isEmpty) {
        // 默认选择第一个平台
        final sites = LiveManager().allSites;
        if (sites.isNotEmpty) {
          platformId = sites.first.id;
        }
      }
      
      if (platformId != null) {
        LiveManager().setCurrentSite(platformId);
        _currentPlatformId = platformId;
      }
      
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('直播模块初始化失败: $e');
      setState(() => _isInitialized = true);
    }
  }

  void _switchPlatform(String platformId) {
    setState(() => _currentPlatformId = platformId);
    LiveManager().setCurrentSite(platformId);
  }

  void _onPlatformChanged(String platformId) {
    _switchPlatform(platformId);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化直播模块...'),
            ],
          ),
        ),
      );
    }

    if (_currentPlatformId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('直播')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.live_tv, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('暂无可用的直播平台'),
              SizedBox(height: 8),
              Text('请检查网络连接或重试'),
            ],
          ),
        ),
      );
    }

    return LivePage(
      key: ValueKey(_currentPlatformId), // 使用 key 强制重建
      platformId: _currentPlatformId!,
      onPlatformChanged: _onPlatformChanged,
    );
  }
}
