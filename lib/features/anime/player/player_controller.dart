import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'player_controller.g.dart';

abstract class _PlayerController with Store {
  // 弹幕控制
  late DanmakuController danmakuController;
  @observable
  bool danmakuOn = false;

  // 视频比例类型
  @observable
  int aspectRatioType = 1;

  // 视频音量/亮度
  @observable
  double volume = -1;
  @observable
  double brightness = 0;

  // 播放器界面控制
  @observable
  bool lockPanel = false;
  @observable
  bool showVideoController = true;
  @observable
  bool showSeekTime = false;
  @observable
  bool showBrightness = false;
  @observable
  bool showVolume = false;
  @observable
  bool showPlaySpeed = false;
  @observable
  bool brightnessSeeking = false;
  @observable
  bool volumeSeeking = false;
  @observable
  bool canHidePlayerPanel = true;

  // 视频地址
  String videoUrl = '';

  // 播放器实体
  Player? mediaPlayer;
  VideoController? videoController;

  // 播放器面板状态
  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  late Box setting;
  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool lowMemoryMode = false;
  bool autoPlay = true;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  // 播放器实时状态
  bool get playerPlaying => mediaPlayer?.state.playing ?? false;
  bool get playerBuffering => mediaPlayer?.state.buffering ?? false;
  bool get playerCompleted => mediaPlayer?.state.completed ?? false;
  double get playerVolume => mediaPlayer?.state.volume ?? 0.0;
  Duration get playerPosition => mediaPlayer?.state.position ?? Duration.zero;
  Duration get playerBuffer => mediaPlayer?.state.buffer ?? Duration.zero;
  Duration get playerDuration => mediaPlayer?.state.duration ?? Duration.zero;

  Future<void> init(String url, {int offset = 0, Map<String, String>? httpHeaders}) async {
    videoUrl = url;
    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    playerSpeed = 1.0;

    try {
      // 先清理之前的播放器实例
      await dispose();
    } catch (e) {
      debugPrint('清理播放器时出错: $e');
    }

    try {
      mediaPlayer = await createVideoController(offset: offset, httpHeaders: httpHeaders);

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        volume = volume != -1 ? volume : 100;
        await setVolume(volume);
      } else {
        await FlutterVolumeController.getVolume().then((value) {
          volume = (value ?? 0.0) * 100;
        });
      }
      
      setPlaybackSpeed(playerSpeed);
      loading = false;
    } catch (e) {
      debugPrint('播放器初始化失败: $e');
      loading = false;
      rethrow;
    }
  }

  Future<Player> createVideoController({int offset = 0, Map<String, String>? httpHeaders}) async {
    hAenable = true;
    hardwareDecoder = 'auto-safe';
    androidEnableOpenSLES = true;
    lowMemoryMode = false; // 可以后续从设置中读取
    autoPlay = true;

    mediaPlayer = Player(
      configuration: PlayerConfiguration(
        // 根据内存模式调整缓冲区大小
        bufferSize: lowMemoryMode ? 15 * 1024 * 1024 : 1500 * 1024 * 1024, // 15MB vs 1.5GB
        osc: false,
        logLevel: MPVLogLevel.warn,
      ),
    );

    var pp = mediaPlayer!.platform as NativePlayer;
    
    // Kazumi的优化配置
    try {
      // 启用双重缓存（硬盘+内存）
      // await pp.setProperty("demuxer-cache-dir", await getPlayerTempPath());
      
      // 音频时间拉伸算法，支持最高8倍速播放
      await pp.setProperty("af", "scaletempo2=max-speed=8");
      
      if (Platform.isAndroid) {
        await pp.setProperty("volume-max", "100");
        if (androidEnableOpenSLES) {
          await pp.setProperty("ao", "opensles"); // 更好的Android音频输出
        } else {
          await pp.setProperty("ao", "audiotrack");
        }
      }
    } catch (e) {
      debugPrint('播放器属性设置失败: $e');
    }

    await mediaPlayer!.setAudioTrack(AudioTrack.auto());

    videoController = VideoController(
      mediaPlayer!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: hAenable,
        hwdec: hAenable ? hardwareDecoder : 'no',
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    
    mediaPlayer!.setPlaylistMode(PlaylistMode.none);

    // Error handling
    mediaPlayer!.stream.error.listen((event) {
      debugPrint('Player error: $event');
    });

    // 监听播放状态变化
    mediaPlayer!.stream.playing.listen((playing) {
      this.playing = playing;
      debugPrint('播放状态变化: $playing');
    });

    // 监听缓冲状态
    mediaPlayer!.stream.buffering.listen((buffering) {
      isBuffering = buffering;
      debugPrint('缓冲状态: $buffering');
    });

    // 使用HTTP头信息打开媒体
    await mediaPlayer!.open(
      Media(
        videoUrl,
        start: Duration(seconds: offset),
        httpHeaders: httpHeaders ?? {},
      ),
      play: autoPlay,
    );

    return mediaPlayer!;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playerSpeed = speed;
    try {
      mediaPlayer?.setRate(speed);
    } catch (e) {
      debugPrint('Failed to set playback speed: $e');
    }
  }

  Future<void> setVolume(double value) async {
    value = value.clamp(0.0, 100.0);
    volume = value;
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await mediaPlayer?.setVolume(value);
      } else {
        await FlutterVolumeController.updateShowSystemUI(false);
        await FlutterVolumeController.setVolume(value / 100);
      }
    } catch (_) {}
  }

  Future<void> playOrPause() async {
    if (mediaPlayer?.state.playing ?? false) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration duration) async {
    currentPosition = duration;
    danmakuController.clear();
    await mediaPlayer?.seek(duration);
  }

  Future<void> pause() async {
    danmakuController.pause();
    await mediaPlayer?.pause();
    playing = false;
  }

  Future<void> play() async {
    danmakuController.resume();
    await mediaPlayer?.play();
    playing = true;
  }

  Future<void> dispose() async {
    try {
      if (mediaPlayer != null) {
        await mediaPlayer!.dispose();
        mediaPlayer = null;
      }
      videoController = null;
    } catch (e) {
      debugPrint('播放器销毁时出错: $e');
    }
  }

  Future<void> stop() async {
    try {
      await mediaPlayer?.stop();
      loading = true;
    } catch (_) {}
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    return await mediaPlayer?.screenshot(format: format);
  }
}

class PlayerController = _PlayerController with _$PlayerController;