import 'dart:async';
import 'dart:io';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'player_controller.dart';

class PlayerItem extends StatefulWidget {
  final PlayerController playerController;
  final VoidCallback onBackPressed;
  final String episodeTitle;

  const PlayerItem({
    super.key,
    required this.playerController,
    required this.onBackPressed,
    required this.episodeTitle,
  });

  @override
  State<PlayerItem> createState() => _PlayerItemState();
}

class _PlayerItemState extends State<PlayerItem>
    with SingleTickerProviderStateMixin {
  Timer? hideTimer;
  Timer? playerTimer;

  AnimationController? animationController;
  double lastPlayerSpeed = 1.0;
  
  // 全屏状态
  bool _isFullScreen = false;
  // 锁定控制面板
  bool _isLocked = false;
  // 手势提示
  String _gestureTip = '';
  bool _showGestureTip = false;

  // 弹幕设置
  final _danmuKey = GlobalKey();
  final double _opacity = 1.0;
  final double _fontSize = 25.0;
  final double _danmakuArea = 1.0;
  final bool _hideTop = false;
  final bool _hideBottom = true;
  final bool _hideScroll = false;
  final bool _massiveMode = false;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    playerTimer = getPlayerTimer();
    
    // 初始显示控制面板
    widget.playerController.showVideoController = true;
    displayVideoController();
  }

  @override
  void dispose() {
    try {
      playerTimer?.cancel();
      hideTimer?.cancel();
      animationController?.dispose();
      // 退出全屏时恢复
      if (_isFullScreen) {
        _exitFullScreen();
      }
    } catch (e) {
      debugPrint('PlayerItem dispose error: $e');
    }
    super.dispose();
  }

  void _handleTap() {
    if (_isLocked) {
      setState(() {
        widget.playerController.showVideoController = !widget.playerController.showVideoController;
      });
      if (widget.playerController.showVideoController) {
        startHideTimer();
      }
      return;
    }
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      widget.playerController.playOrPause();
    } else {
      if (widget.playerController.showVideoController) {
        hideVideoController();
      } else {
        displayVideoController();
      }
    }
  }

  void _handleDoubleTap() {
    if (_isLocked) return;
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _toggleFullScreen();
    } else {
      widget.playerController.playOrPause();
      _showGestureTipText(widget.playerController.playing ? '暂停' : '播放');
    }
  }
  
  void _showGestureTipText(String text) {
    setState(() {
      _gestureTip = text;
      _showGestureTip = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _showGestureTip = false);
      }
    });
  }
  
  void _toggleFullScreen() {
    if (_isFullScreen) {
      _exitFullScreen();
    } else {
      _enterFullScreen();
    }
  }
  
  Future<void> _enterFullScreen() async {
    setState(() => _isFullScreen = true);
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面端使用 window_manager
      await windowManager.setFullScreen(true);
    } else {
      // 移动端使用系统UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }
  
  Future<void> _exitFullScreen() async {
    setState(() => _isFullScreen = false);
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面端使用 window_manager
      await windowManager.setFullScreen(false);
    } else {
      // 移动端恢复系统UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }
  
  void _toggleLock() {
    setState(() => _isLocked = !_isLocked);
    _showGestureTipText(_isLocked ? '已锁定' : '已解锁');
  }
  
  void _seekForward([int seconds = 10]) {
    final newPosition = widget.playerController.currentPosition + Duration(seconds: seconds);
    final maxPosition = widget.playerController.duration;
    widget.playerController.seek(newPosition > maxPosition ? maxPosition : newPosition);
    _showGestureTipText('+${seconds}s');
  }
  
  void _seekBackward([int seconds = 10]) {
    final newPosition = widget.playerController.currentPosition - Duration(seconds: seconds);
    widget.playerController.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
    _showGestureTipText('-${seconds}s');
  }

  void displayVideoController() {
    animationController?.forward();
    hideTimer?.cancel();
    startHideTimer();
    setState(() {
      widget.playerController.showVideoController = true;
    });
  }

  void hideVideoController() {
    animationController?.reverse();
    hideTimer?.cancel();
    setState(() {
      widget.playerController.showVideoController = false;
    });
  }

  void startHideTimer() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && widget.playerController.canHidePlayerPanel) {
        hideVideoController();
      }
    });
  }
  
  /// 鼠标移动时调用 - 显示控制面板并重置隐藏计时器
  void _onMouseMove() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (!widget.playerController.showVideoController) {
        displayVideoController();
      } else {
        // 重置隐藏计时器
        hideTimer?.cancel();
        startHideTimer();
      }
    }
  }

  Timer getPlayerTimer() {
    return Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      widget.playerController.playing = widget.playerController.playerPlaying;
      widget.playerController.isBuffering = widget.playerController.playerBuffering;
      widget.playerController.currentPosition = widget.playerController.playerPosition;
      widget.playerController.buffer = widget.playerController.playerBuffer;
      widget.playerController.duration = widget.playerController.playerDuration;
      widget.playerController.completed = widget.playerController.playerCompleted;

      if (!widget.playerController.volumeSeeking) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          widget.playerController.volume = widget.playerController.playerVolume;
        } else {
          FlutterVolumeController.getVolume().then((value) {
            widget.playerController.volume = (value ?? 0.0) * 100;
          });
        }
      }

      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux &&
          !widget.playerController.brightnessSeeking) {
        ScreenBrightnessPlatform.instance.application.then((value) {
          widget.playerController.brightness = value;
        });
      }
    });
  }

  Future<void> setBrightness(double value) async {
    try {
      await ScreenBrightnessPlatform.instance.setApplicationScreenBrightness(value);
    } catch (_) {}
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _showSpeedMenu(BuildContext context) {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '播放速度',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: speeds.map((speed) {
                  final isSelected = (widget.playerController.playerSpeed - speed).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${speed}x'),
                    selected: isSelected,
                    onSelected: (_) {
                      widget.playerController.setPlaybackSpeed(speed);
                      Navigator.pop(context);
                    },
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    backgroundColor: Colors.grey.shade800,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '播放设置',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.aspect_ratio, color: Colors.white),
                title: const Text('画面比例', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _getAspectRatioText(widget.playerController.aspectRatioType),
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAspectRatioMenu(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.white),
                title: const Text('截图', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final screenshot = await widget.playerController.screenshot();
                  if (screenshot != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('截图已保存到剪贴板')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _getAspectRatioText(int type) {
    switch (type) {
      case 0: return '适应';
      case 1: return '拉伸';
      case 2: return '铺满';
      case 3: return '16:9';
      case 4: return '4:3';
      default: return '适应';
    }
  }

  void _showAspectRatioMenu(BuildContext context) {
    final ratios = ['适应', '拉伸', '铺满', '16:9', '4:3'];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '画面比例',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...ratios.asMap().entries.map((entry) {
                final isSelected = widget.playerController.aspectRatioType == entry.key;
                return ListTile(
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                  onTap: () {
                    widget.playerController.aspectRatioType = entry.key;
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    
    return Observer(
      builder: (context) {
        return MouseRegion(
          // 监听鼠标移动，而不是进入/离开
          onHover: (_) => _onMouseMove(),
          onExit: (_) {
            // 鼠标离开窗口时，4秒后隐藏
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              hideTimer?.cancel();
              startHideTimer();
            }
          },
          child: Container(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Video surface
                if (widget.playerController.videoController != null)
                  Video(controller: widget.playerController.videoController!),

                // Loading indicator
                if (widget.playerController.isBuffering || widget.playerController.loading)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),

                // Danmaku screen
                Positioned.fill(
                  child: DanmakuScreen(
                    key: _danmuKey,
                    createdController: (DanmakuController controller) {
                      widget.playerController.danmakuController = controller;
                    },
                    option: DanmakuOption(
                      hideTop: _hideTop,
                      hideScroll: _hideScroll,
                      hideBottom: _hideBottom,
                      area: _danmakuArea,
                      opacity: _opacity,
                      fontSize: _fontSize,
                      duration: (8.0 / widget.playerController.playerSpeed).round(),
                      massiveMode: _massiveMode,
                    ),
                  ),
                ),

                // Gesture detector (不再处理鼠标悬停)
                Positioned.fill(child: _buildGestureLayer(context)),

                // Top controls bar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 0,
                  right: 0,
                  top: (widget.playerController.showVideoController && !_isLocked) 
                      ? 0 : -(56 + padding.top),
                  child: _buildTopBar(context, padding),
                ),

                // Bottom controls bar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 0,
                  right: 0,
                  bottom: (widget.playerController.showVideoController && !_isLocked) 
                      ? 0 : -120,
                  child: _buildBottomBar(context, padding),
                ),

                // Lock buttons (mobile/fullscreen only)
                if (_isFullScreen || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS))
                  ..._buildLockButtons(padding),

                // Gesture tip overlay
                if (_showGestureTip)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _gestureTip,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                // Volume indicator
                if (widget.playerController.showVolume)
                  Positioned(
                    right: 24,
                    top: 0,
                    bottom: 0,
                    child: Center(child: _buildVerticalIndicator(
                      icon: Icons.volume_up,
                      value: widget.playerController.volume / 100,
                      label: '${widget.playerController.volume.round()}%',
                    )),
                  ),

                // Brightness indicator
                if (widget.playerController.showBrightness)
                  Positioned(
                    left: 24,
                    top: 0,
                    bottom: 0,
                    child: Center(child: _buildVerticalIndicator(
                      icon: Icons.brightness_6,
                      value: widget.playerController.brightness,
                      label: '${(widget.playerController.brightness * 100).round()}%',
                    )),
                  ),

                // Speed indicator (long press)
                if (widget.playerController.showPlaySpeed)
                  Positioned(
                    top: padding.top + 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fast_forward, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${widget.playerController.playerSpeed}x 快进中',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  List<Widget> _buildLockButtons(EdgeInsets padding) {
    return [
      AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        left: widget.playerController.showVideoController 
            ? padding.left + 12 : -(48 + padding.left),
        top: 0,
        bottom: 0,
        child: _buildLockButton(),
      ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        right: widget.playerController.showVideoController 
            ? padding.right + 12 : -(48 + padding.right),
        top: 0,
        bottom: 0,
        child: _buildLockButton(),
      ),
    ];
  }
  
  Widget _buildGestureLayer(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: _handleDoubleTap,
      onLongPressStart: (_) {
        if (_isLocked) return;
        setState(() => widget.playerController.showPlaySpeed = true);
        lastPlayerSpeed = widget.playerController.playerSpeed;
        widget.playerController.setPlaybackSpeed(2.0);
      },
      onLongPressEnd: (_) {
        if (_isLocked) return;
        setState(() => widget.playerController.showPlaySpeed = false);
        widget.playerController.setPlaybackSpeed(lastPlayerSpeed);
      },
      onHorizontalDragStart: (_) {
        if (_isLocked) return;
        if (!widget.playerController.showVideoController) {
          animationController?.forward();
        }
        widget.playerController.canHidePlayerPanel = false;
      },
      onHorizontalDragUpdate: (details) {
        if (_isLocked) return;
        widget.playerController.showSeekTime = true;
        playerTimer?.cancel();
        widget.playerController.pause();
        final double scale = 180000 / MediaQuery.sizeOf(context).width;
        int ms = (widget.playerController.currentPosition.inMilliseconds +
                (details.delta.dx * scale).round())
            .clamp(0, widget.playerController.duration.inMilliseconds);
        widget.playerController.currentPosition = Duration(milliseconds: ms);
        _showGestureTipText(_formatDuration(widget.playerController.currentPosition));
      },
      onHorizontalDragEnd: (_) {
        if (_isLocked) return;
        widget.playerController.play();
        widget.playerController.seek(widget.playerController.currentPosition);
        widget.playerController.canHidePlayerPanel = true;
        if (!widget.playerController.showVideoController) {
          animationController?.reverse();
        } else {
          hideTimer?.cancel();
          startHideTimer();
        }
        playerTimer?.cancel();
        playerTimer = getPlayerTimer();
        widget.playerController.showSeekTime = false;
        setState(() => _showGestureTip = false);
      },
      onVerticalDragUpdate: (details) async {
        if (_isLocked) return;
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return;
        
        final double totalWidth = MediaQuery.sizeOf(context).width;
        final double totalHeight = MediaQuery.sizeOf(context).height;
        final double tapPosition = details.localPosition.dx;
        final double delta = details.delta.dy;

        if (tapPosition < totalWidth / 2) {
          widget.playerController.brightnessSeeking = true;
          widget.playerController.showBrightness = true;
          final double brightness = widget.playerController.brightness - delta / (totalHeight * 2);
          setBrightness(brightness.clamp(0.0, 1.0));
          widget.playerController.brightness = brightness.clamp(0.0, 1.0);
        } else {
          widget.playerController.volumeSeeking = true;
          widget.playerController.showVolume = true;
          final double volume = widget.playerController.volume - delta / (totalHeight * 0.03);
          widget.playerController.setVolume(volume);
        }
      },
      onVerticalDragEnd: (_) {
        if (_isLocked) return;
        if (widget.playerController.volumeSeeking) {
          widget.playerController.volumeSeeking = false;
          Future.delayed(const Duration(seconds: 1), () {
            FlutterVolumeController.updateShowSystemUI(true);
          });
        }
        if (widget.playerController.brightnessSeeking) {
          widget.playerController.brightnessSeeking = false;
        }
        widget.playerController.showVolume = false;
        widget.playerController.showBrightness = false;
      },
      child: Container(color: Colors.transparent, width: double.infinity, height: double.infinity),
    );
  }

  
  Widget _buildTopBar(BuildContext context, EdgeInsets padding) {
    return Container(
      height: 56 + padding.top,
      padding: EdgeInsets.only(
        left: padding.left + 8,
        right: padding.right + 8,
        top: padding.top,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_isFullScreen) {
                _exitFullScreen();
              } else {
                widget.onBackPressed();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.episodeTitle,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            onPressed: () async {
              final screenshot = await widget.playerController.screenshot();
              if (screenshot != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('截图已保存')),
                );
              }
            },
            tooltip: '截图',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showSettingsMenu(context),
            tooltip: '设置',
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomBar(BuildContext context, EdgeInsets padding) {
    return Container(
      padding: EdgeInsets.only(
        left: padding.left + 16,
        right: padding.right + 16,
        bottom: padding.bottom + 8,
        top: 8,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar row
          Row(
            children: [
              Text(
                _formatDuration(widget.playerController.currentPosition),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ProgressBar(
                  progress: widget.playerController.currentPosition,
                  buffered: widget.playerController.buffer,
                  total: widget.playerController.duration,
                  onSeek: (duration) => widget.playerController.seek(duration),
                  progressBarColor: Theme.of(context).colorScheme.primary,
                  baseBarColor: Colors.white.withValues(alpha: 0.3),
                  bufferedBarColor: Colors.white.withValues(alpha: 0.5),
                  thumbColor: Theme.of(context).colorScheme.primary,
                  barHeight: 3.0,
                  thumbRadius: 6.0,
                  timeLabelLocation: TimeLabelLocation.none,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(widget.playerController.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Control buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(Icons.replay_10, () => _seekBackward(10), '快退10秒'),
              _buildControlButton(
                widget.playerController.playing ? Icons.pause : Icons.play_arrow,
                () => widget.playerController.playOrPause(),
                widget.playerController.playing ? '暂停' : '播放',
                size: 36,
              ),
              _buildControlButton(Icons.forward_10, () => _seekForward(10), '快进10秒'),
              _buildControlButton(
                widget.playerController.danmakuOn ? Icons.subtitles : Icons.subtitles_off_outlined,
                () => setState(() => widget.playerController.danmakuOn = !widget.playerController.danmakuOn),
                widget.playerController.danmakuOn ? '关闭弹幕' : '开启弹幕',
              ),
              _buildTextButton('${widget.playerController.playerSpeed}x', () => _showSpeedMenu(context), '播放速度'),
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                _buildVolumeControl(),
              _buildControlButton(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                _toggleFullScreen,
                _isFullScreen ? '退出全屏' : '全屏',
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildLockButton() {
    return Center(
      child: GestureDetector(
        onTap: _toggleLock,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _isLocked ? Icons.lock : Icons.lock_open,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
  
  Widget _buildControlButton(IconData icon, VoidCallback onPressed, String tooltip, {double size = 24}) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: size),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
  
  Widget _buildTextButton(String text, VoidCallback onPressed, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }
  
  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            widget.playerController.volume > 0 ? Icons.volume_up : Icons.volume_off,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () {
            widget.playerController.setVolume(widget.playerController.volume > 0 ? 0.0 : 100.0);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: widget.playerController.volume.clamp(0.0, 100.0),
              min: 0.0,
              max: 100.0,
              onChanged: (value) => widget.playerController.setVolume(value),
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildVerticalIndicator({required IconData icon, required double value, required String label}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            width: 4,
            child: RotatedBox(
              quarterTurns: -1,
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
