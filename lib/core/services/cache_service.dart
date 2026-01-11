import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
import 'manga_image_provider.dart';

/// 缓存管理服务
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  /// 获取总缓存大小（字节）
  Future<int> getTotalCacheSize() async {
    int totalSize = 0;

    // 1. 内存图片缓存
    final imageCache = MangaImageCache();
    final stats = imageCache.getCacheStats();
    totalSize += stats['totalSize'] as int;

    // 2. 应用专属缓存目录 (cached_network_image 等)
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appSupportDir.path}/cache');
      if (await cacheDir.exists()) {
        totalSize += await _getDirectorySize(cacheDir);
      }
    } catch (e) {
      Logger.error('获取应用缓存目录大小失败: $e');
    }

    // 3. 应用专属临时目录
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final tempDir = Directory('${appSupportDir.path}/temp');
      if (await tempDir.exists()) {
        totalSize += await _getDirectorySize(tempDir);
      }
    } catch (e) {
      Logger.error('获取应用临时目录大小失败: $e');
    }

    return totalSize;
  }

  /// 获取格式化的缓存大小字符串
  Future<String> getFormattedCacheSize() async {
    final size = await getTotalCacheSize();
    return _formatBytes(size);
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    Logger.info('开始清理缓存...');

    // 1. 清理内存图片缓存
    MangaImageCache().clearAll();

    // 2. 清理 Flutter 图片缓存
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 3. 清理应用专属缓存目录
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appSupportDir.path}/cache');
      if (await cacheDir.exists()) {
        await _clearDirectory(cacheDir);
      }
    } catch (e) {
      Logger.error('清理应用缓存目录失败: $e');
    }

    // 4. 清理应用专属临时目录
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final tempDir = Directory('${appSupportDir.path}/temp');
      if (await tempDir.exists()) {
        await _clearDirectory(tempDir);
      }
    } catch (e) {
      Logger.error('清理应用临时目录失败: $e');
    }

    Logger.info('缓存清理完成');
  }

  /// 计算目录大小
  Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              size += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      Logger.error('计算目录大小失败: ${dir.path}, $e');
    }
    return size;
  }

  /// 清空目录内容（保留目录本身）
  Future<void> _clearDirectory(Directory dir) async {
    try {
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            Logger.error('删除文件失败: ${entity.path}, $e');
          }
        }
      }
    } catch (e) {
      Logger.error('清空目录失败: ${dir.path}, $e');
    }
  }

  /// 格式化字节数为可读字符串
  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
}
