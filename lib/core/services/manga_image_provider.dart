import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/logger.dart';
import 'smart_network_service_v2.dart';
import 'jm_image_decoder.dart';

/// 漫画图片提供器 - 使用智能网络服务加载图片
/// 支持 CDN 回退和 WebView 渐进式下载
/// 支持 JM 图片解密
class MangaImageProvider extends ImageProvider<MangaImageProvider> {
  final String sourceKey;
  final String imageUrl;
  final Map<String, String>? headers;
  final String? referer;
  final List<String>? cdnFallbacks;
  final bool forceWebView;
  final double scale;
  final int? epId; // 章节ID，用于JM解密

  static final Map<String, _MangaImageFailureState> _failureStates = {};

  const MangaImageProvider({
    required this.sourceKey,
    required this.imageUrl,
    this.headers,
    this.referer,
    this.cdnFallbacks,
    this.forceWebView = false,
    this.scale = 1.0,
    this.epId,
  });

  @override
  Future<MangaImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MangaImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(MangaImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.imageUrl,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Source', key.sourceKey),
        DiagnosticsProperty<String>('Image URL', key.imageUrl),
      ],
    );
  }

  /// 异步加载图片
  Future<ui.Codec> _loadAsync(MangaImageProvider key, ImageDecoderCallback decode) async {
    try {
      Logger.info('加载漫画图片: ${key.imageUrl}');

      final cacheKey = '${key.sourceKey}|${key.imageUrl}|${key.forceWebView ? 'wv' : 'dio'}';
      final cached = MangaImageCache().getCachedImage(cacheKey);
      if (cached != null) {
        final buffer = await ui.ImmutableBuffer.fromUint8List(cached);
        return await decode(buffer);
      }

      final now = DateTime.now();
      final state = _failureStates[cacheKey];
      if (state != null && state.nextAllowedAt != null && now.isBefore(state.nextAllowedAt!)) {
        throw Exception(
          '图片加载失败(冷却中): ${state.lastError ?? 'unknown'}',
        );
      }
      
      final networkService = SmartNetworkServiceV2();
      final result = await networkService.downloadImage(
        key.imageUrl,
        headers: key.headers,
        referer: key.referer,
        cdnFallbacks: key.cdnFallbacks,
        forceWebView: key.forceWebView,
      );

      if (result.isFailure || result.data == null) {
        _recordFailure(cacheKey, result.error ?? 'unknown');
        throw Exception('图片加载失败: ${result.error}');
      }

      _failureStates.remove(cacheKey);
      
      // 处理图片数据（可能需要JM解密）
      Uint8List imageData = result.data!;
      
      if (JmImageDecoder.needsDecode(key.sourceKey)) {
        // 尝试从URL或参数获取epId
        int? epId = key.epId ?? JmImageDecoder.extractEpIdFromUrl(key.imageUrl);
        if (epId != null) {
          try {
            Logger.info('JM图片解密: epId=$epId, url=${key.imageUrl}');
            imageData = await JmImageDecoder.decodeImage(imageData, epId, key.imageUrl);
            Logger.info('JM图片解密成功');
          } catch (e) {
            Logger.error('JM图片解密失败: $e');
            // 解密失败时使用原始图片
          }
        }
      }
      
      MangaImageCache().cacheImage(cacheKey, imageData);

      Logger.info('图片加载成功: ${key.imageUrl} (${imageData.length} bytes)');
      
      final buffer = await ui.ImmutableBuffer.fromUint8List(imageData);
      return await decode(buffer);
    } catch (e) {
      final cacheKey = '${key.sourceKey}|${key.imageUrl}|${key.forceWebView ? 'wv' : 'dio'}';
      _recordFailure(cacheKey, e.toString());
      Logger.error('图片加载异常: ${key.imageUrl}, 错误: $e');
      rethrow;
    }
  }

  static void _recordFailure(String cacheKey, String error) {
    final now = DateTime.now();
    final existing = _failureStates[cacheKey];
    final next = existing ?? _MangaImageFailureState();
    next.lastAttemptAt = now;
    next.lastError = error;
    next.attempts = (next.attempts ?? 0) + 1;

    final attempts = next.attempts ?? 1;
    if (attempts >= 6) {
      next.nextAllowedAt = now.add(const Duration(minutes: 5));
    } else if (attempts >= 3) {
      next.nextAllowedAt = now.add(const Duration(seconds: 45));
    } else {
      next.nextAllowedAt = now.add(const Duration(seconds: 5));
    }

    _failureStates[cacheKey] = next;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is MangaImageProvider &&
        other.sourceKey == sourceKey &&
        other.imageUrl == imageUrl &&
        other.scale == scale &&
        other.forceWebView == forceWebView &&
        other.epId == epId;
  }

  @override
  int get hashCode => Object.hash(sourceKey, imageUrl, scale, forceWebView, epId);

  @override
  String toString() => '${objectRuntimeType(this, 'MangaImageProvider')}('
      'sourceKey: "$sourceKey", '
      'imageUrl: "$imageUrl", '
      'scale: $scale, '
      'forceWebView: $forceWebView, '
      'epId: $epId)';
}

class _MangaImageFailureState {
  int? attempts;
  DateTime? lastAttemptAt;
  DateTime? nextAllowedAt;
  String? lastError;
}

/// 漫画图片组件 - 使用独立网络层的图片显示组件
class MangaImage extends StatelessWidget {
  final String sourceKey;
  final String imageUrl;
  final Map<String, String>? headers;
  final String? referer;
  final List<String>? cdnFallbacks;
  final bool forceWebView;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double scale;
  final int? epId; // 章节ID，用于JM解密

  const MangaImage({
    super.key,
    required this.sourceKey,
    required this.imageUrl,
    this.headers,
    this.referer,
    this.cdnFallbacks,
    this.forceWebView = false,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.scale = 1.0,
    this.epId,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      image: MangaImageProvider(
        sourceKey: sourceKey,
        imageUrl: imageUrl,
        headers: headers,
        referer: referer,
        cdnFallbacks: cdnFallbacks,
        forceWebView: forceWebView,
        scale: scale,
        epId: epId,
      ),
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: placeholder != null 
          ? (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return placeholder!;
            }
          : null,
      errorBuilder: errorWidget != null
          ? (context, error, stackTrace) => errorWidget!
          : (context, error, stackTrace) => _buildDefaultErrorWidget(context, error),
    );
  }

  /// 构建默认错误组件
  Widget _buildDefaultErrorWidget(BuildContext context, Object error) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image,
            size: 32,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 8),
          Text(
            '图片加载失败',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 漫画图片缓存管理器
class MangaImageCache {
  static final MangaImageCache _instance = MangaImageCache._internal();
  factory MangaImageCache() => _instance;
  MangaImageCache._internal();

  final Map<String, Uint8List> _memoryCache = {};
  final int _maxCacheSize = 50 * 1024 * 1024; // 50MB
  int _currentCacheSize = 0;

  /// 获取缓存的图片数据
  Uint8List? getCachedImage(String key) {
    return _memoryCache[key];
  }

  /// 缓存图片数据
  void cacheImage(String key, Uint8List imageData) {
    // 检查缓存大小
    if (_currentCacheSize + imageData.length > _maxCacheSize) {
      _evictOldestEntries(imageData.length);
    }

    _memoryCache[key] = imageData;
    _currentCacheSize += imageData.length;
    
    Logger.info('缓存图片: $key (${imageData.length} bytes), 总缓存: ${_currentCacheSize ~/ 1024}KB');
  }

  /// 清理最旧的缓存条目
  void _evictOldestEntries(int requiredSpace) {
    final entries = _memoryCache.entries.toList();
    
    for (final entry in entries) {
      _memoryCache.remove(entry.key);
      _currentCacheSize -= entry.value.length;
      
      if (_currentCacheSize + requiredSpace <= _maxCacheSize) {
        break;
      }
    }
    
    Logger.info('清理图片缓存，当前大小: ${_currentCacheSize ~/ 1024}KB');
  }

  /// 清空所有缓存
  void clearAll() {
    _memoryCache.clear();
    _currentCacheSize = 0;
    Logger.info('清空所有图片缓存');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'entryCount': _memoryCache.length,
      'totalSize': _currentCacheSize,
      'maxSize': _maxCacheSize,
      'usagePercent': (_currentCacheSize / _maxCacheSize * 100).round(),
    };
  }
}