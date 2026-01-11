import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:dio/dio.dart';

import '../../../core/models/anime_item.dart';
import '../../../core/services/kazumi_video_parser.dart';
import 'player_controller.dart';
import 'player_item.dart';

class VideoPlayerPage extends StatefulWidget {
  final AnimeEpisode episode;
  final String animeTitle;
  final String ruleKey; // 添加规则键

  const VideoPlayerPage({
    super.key,
    required this.episode,
    required this.animeTitle,
    required this.ruleKey,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late PlayerController playerController;
  bool isInitialized = false;
  String? error;

  @override
  void initState() {
    super.initState();
    // Initialize MediaKit
    MediaKit.ensureInitialized();
    
    playerController = PlayerController();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        error = null;
      });
      
      // Store context before async operations
      final currentContext = context;
      
      // 加载规则配置
      KazumiRuleConfig? ruleConfig;
      try {
        final ruleContent = await DefaultAssetBundle.of(currentContext).loadString('assets/rules/anime/${widget.ruleKey}.json');
        final ruleJson = json.decode(ruleContent);
        ruleConfig = KazumiRuleConfig.fromJson(ruleJson);
        print('[Kazumi Player] 加载规则配置: ${widget.ruleKey}');
        print('[Kazumi Player] 规则配置: useWebview=${ruleConfig.useWebview}, useNativePlayer=${ruleConfig.useNativePlayer}');
      } catch (e) {
        print('[Kazumi Player] 加载规则配置失败: $e');
        // 使用默认配置
        ruleConfig = KazumiRuleConfig();
      }
      
      // 使用Kazumi完整解析器
      print('[Kazumi Player] 开始解析视频URL: ${widget.episode.episodeUrl}');
      final parseResult = await KazumiVideoParser.parseVideoUrl(
        widget.episode.episodeUrl,
        ruleConfig,
        context: currentContext.mounted ? currentContext : null,
      );
      
      if (!parseResult.isSuccess || parseResult.videoUrl == null) {
        throw Exception(parseResult.errorMessage ?? '无法从页面中提取视频URL，可能是不支持的视频源或网络问题');
      }
      
      print('[Kazumi Player] 解析到视频URL: ${parseResult.videoUrl}');
      print('[Kazumi Player] HTTP头信息: ${parseResult.httpHeaders}');
      
      // 测试：先尝试直接访问视频URL检查是否可达
      try {
        final testResponse = await Dio().head(
          parseResult.videoUrl!,
          options: Options(
            headers: parseResult.httpHeaders,
            validateStatus: (status) => status! < 500,
          ),
        );
        print('[Kazumi Player] 视频URL可达性测试: ${testResponse.statusCode}');
        print('[Kazumi Player] Content-Type: ${testResponse.headers.value('content-type')}');
        print('[Kazumi Player] Content-Length: ${testResponse.headers.value('content-length')}');
      } catch (e) {
        print('[Kazumi Player] 视频URL可达性测试失败: $e');
        // 继续尝试播放，可能是服务器不支持HEAD请求
      }
      
      // 使用HTTP头信息初始化播放器
      await playerController.init(
        parseResult.videoUrl!,
        httpHeaders: parseResult.httpHeaders,
      );
      
      if (mounted) {
        setState(() {
          isInitialized = true;
        });
      }
    } catch (e) {
      print('[Kazumi Player] 播放器初始化失败: $e');
      if (mounted) {
        setState(() {
          error = e.toString();
          isInitialized = false;
        });
      }
    }
  }

  void _onBackPressed() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    try {
      playerController.dispose();
    } catch (e) {
      debugPrint('播放器页面销毁时出错: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Video player area
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: _buildPlayerContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    if (error != null) {
      return _buildErrorWidget();
    }

    if (!isInitialized) {
      return _buildLoadingWidget();
    }

    return PlayerItem(
      playerController: playerController,
      onBackPressed: _onBackPressed,
      episodeTitle: '${widget.animeTitle} - ${widget.episode.title}',
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              '正在解析视频源...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              '播放器加载失败',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _initializePlayer,
                  child: const Text('重试'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _onBackPressed,
                  child: const Text('返回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}