/// Live player page with danmaku support
/// Uses media_kit for video playback and canvas_danmaku for danmaku
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/services/live_manager.dart';

class LivePlayerPage extends StatefulWidget {
  final LiveRoomItem room;

  const LivePlayerPage({super.key, required this.room});

  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> {
  LiveRoomDetail? _roomDetail;
  List<LivePlayQuality> _qualities = [];
  LivePlayQuality? _currentQuality;
  List<String> _playUrls = [];
  int _currentLineIndex = 0;
  
  bool _isLoading = true;
  String? _error;
  
  late final Player _player;
  late final VideoController _videoController;
  
  // Danmaku
  LiveDanmaku? _liveDanmaku;
  DanmakuController? _danmakuController;
  bool _showDanmaku = true;
  
  // Controls
  bool _showControls = true;
  Timer? _hideControlsTimer;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _initPlayer();
    _loadRoomDetail();
  }

  void _initPlayer() {
    // Listen for player events
    _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable();
      }
    });
    
    _player.stream.error.listen((error) {
      debugPrint('Player error: $error');
      if (error.isNotEmpty && !error.contains('no sound')) {
        _handlePlayError();
      }
    });
    
    _player.stream.completed.listen((completed) {
      if (completed) {
        _handlePlayEnd();
      }
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _liveDanmaku?.stop();
    _danmakuController?.clear();
    _player.dispose();
    WakelockPlus.disable();
    
    // Reset orientation
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    
    super.dispose();
  }

  Future<void> _loadRoomDetail() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      final detail = await LiveManager().getRoomDetail(roomId: widget.room.roomId);
      _roomDetail = detail;
      
      if (!detail.status) {
        setState(() {
          _isLoading = false;
          _error = '主播未开播';
        });
        return;
      }
      
      // Get qualities
      final qualities = await LiveManager().getPlayQualites(detail: detail);
      _qualities = qualities;
      
      if (qualities.isNotEmpty) {
        _currentQuality = qualities.first;
        await _loadPlayUrls();
      }
      
      // Start danmaku
      _startDanmaku();
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Load room detail error: $e');
      setState(() {
        _isLoading = false;
        _error = '加载失败: $e';
      });
    }
  }

  Future<void> _loadPlayUrls() async {
    if (_roomDetail == null || _currentQuality == null) return;
    
    try {
      final playUrl = await LiveManager().getPlayUrls(
        detail: _roomDetail!,
        quality: _currentQuality!,
      );
      
      _playUrls = playUrl.urls;
      _currentLineIndex = 0;
      
      if (_playUrls.isNotEmpty) {
        await _playStream(_playUrls[_currentLineIndex], playUrl.headers);
      }
    } catch (e) {
      debugPrint('Load play urls error: $e');
      setState(() => _error = '获取播放地址失败');
    }
  }

  Future<void> _playStream(String url, Map<String, String>? headers) async {
    try {
      await _player.open(Media(url, httpHeaders: headers));
    } catch (e) {
      debugPrint('Play stream error: $e');
    }
  }

  void _handlePlayError() {
    // Try next line
    if (_currentLineIndex < _playUrls.length - 1) {
      _currentLineIndex++;
      _playStream(_playUrls[_currentLineIndex], null);
    } else {
      setState(() => _error = '播放失败，请尝试切换线路');
    }
  }

  void _handlePlayEnd() {
    // Try next line or show offline
    if (_currentLineIndex < _playUrls.length - 1) {
      _currentLineIndex++;
      _playStream(_playUrls[_currentLineIndex], null);
    }
  }

  void _startDanmaku() {
    _liveDanmaku = LiveManager().getDanmaku();
    if (_liveDanmaku == null || _roomDetail?.danmakuData == null) return;
    
    _liveDanmaku!.onMessage = _onDanmakuMessage;
    _liveDanmaku!.onClose = (msg) => debugPrint('Danmaku closed: $msg');
    _liveDanmaku!.onReady = () => debugPrint('Danmaku ready');
    _liveDanmaku!.start(_roomDetail!.danmakuData);
  }

  void _onDanmakuMessage(LiveMessage msg) {
    if (!_showDanmaku || _danmakuController == null) return;
    
    if (msg.type == LiveMessageType.chat) {
      _danmakuController?.addDanmaku(
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        ),
      );
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _resetHideControlsTimer();
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: _qualities.length,
        itemBuilder: (context, index) {
          final quality = _qualities[index];
          final isSelected = quality == _currentQuality;
          return ListTile(
            leading: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
            title: Text(quality.quality),
            onTap: () {
              Navigator.pop(context);
              setState(() => _currentQuality = quality);
              _loadPlayUrls();
            },
          );
        },
      ),
    );
  }

  void _showLineSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: _playUrls.length,
        itemBuilder: (context, index) {
          final isSelected = index == _currentLineIndex;
          final url = _playUrls[index];
          final isFlv = url.contains('.flv');
          return ListTile(
            leading: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
            title: Text('线路 ${index + 1}'),
            trailing: Text(isFlv ? 'FLV' : 'HLS', style: const TextStyle(fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              _currentLineIndex = index;
              _playStream(_playUrls[index], null);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildPlayer(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('正在加载...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadRoomDetail,
            child: const Text('重试'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      onTap: _toggleControls,
      onDoubleTap: _toggleFullScreen,
      child: Stack(
        children: [
          // Video player
          Center(
            child: Video(
              controller: _videoController,
              controls: NoVideoControls,
            ),
          ),
          
          // Danmaku layer
          if (_showDanmaku)
            Positioned.fill(
              child: DanmakuScreen(
                createdController: (controller) {
                  _danmakuController = controller;
                },
                option: DanmakuOption(
                  fontSize: 16,
                  area: 0.8,
                  duration: 8,
                  opacity: 1.0,
                ),
              ),
            ),
          
          // Controls overlay
          _buildControlsOverlay(),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_showControls,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black54],
              stops: [0.0, 0.2, 0.8, 1.0],
            ),
          ),
          child: Column(
            children: [
              // Top bar
              _buildTopBar(),
              
              const Spacer(),
              
              // Bottom bar
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (_isFullScreen) {
                  _toggleFullScreen();
                } else {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                '${_roomDetail?.title ?? widget.room.title} - ${_roomDetail?.userName ?? widget.room.userName}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Refresh
            IconButton(
              onPressed: _loadRoomDetail,
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: '刷新',
            ),
            
            // Danmaku toggle
            IconButton(
              onPressed: () {
                setState(() => _showDanmaku = !_showDanmaku);
                if (!_showDanmaku) _danmakuController?.clear();
              },
              icon: Icon(
                _showDanmaku ? Icons.subtitles : Icons.subtitles_off,
                color: Colors.white,
              ),
              tooltip: _showDanmaku ? '关闭弹幕' : '开启弹幕',
            ),
            
            // Online count
            if (_roomDetail != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _formatOnline(_roomDetail!.online),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            
            const Spacer(),
            
            // Quality selector
            if (_qualities.isNotEmpty)
              TextButton(
                onPressed: _showQualitySelector,
                child: Text(
                  _currentQuality?.quality ?? '清晰度',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            
            // Line selector
            if (_playUrls.length > 1)
              TextButton(
                onPressed: _showLineSelector,
                child: Text(
                  '线路${_currentLineIndex + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            
            // Fullscreen toggle
            IconButton(
              onPressed: _toggleFullScreen,
              icon: Icon(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white,
              ),
              tooltip: _isFullScreen ? '退出全屏' : '全屏',
            ),
          ],
        ),
      ),
    );
  }

  String _formatOnline(int online) {
    if (online >= 10000) {
      return '${(online / 10000).toStringAsFixed(1)}万人观看';
    }
    return '$online人观看';
  }
}
