import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// JM (禁漫天堂) 图片解密服务
/// JM 会将图片切成多个水平条带并打乱顺序，需要按正确顺序重新拼接
class JmImageDecoder {
  static const int _scrambleId = 220980;

  /// 判断是否需要解密
  static bool needsDecode(String sourceKey) {
    return sourceKey == 'jm' || sourceKey.contains('禁漫');
  }

  /// 计算图片分割数
  /// [epId] 章节ID
  /// [imageUrl] 图片URL，用于提取图片名
  static int calculateSegmentCount(int epId, String imageUrl) {
    // 从URL中提取图片名（不含扩展名）
    String pictureName = '';
    final lastSlash = imageUrl.lastIndexOf('/');
    if (lastSlash != -1) {
      final fileName = imageUrl.substring(lastSlash + 1);
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1) {
        pictureName = fileName.substring(0, dotIndex);
      } else {
        pictureName = fileName;
      }
    }

    int num = 0;
    if (epId < _scrambleId) {
      num = 0;
    } else if (epId < 268850) {
      num = 10;
    } else if (epId > 421926) {
      // 新算法
      final str = '$epId$pictureName';
      final bytes = utf8.encode(str);
      final hashResult = md5.convert(bytes);
      final hashStr = hashResult.toString();
      final charCode = hashStr.codeUnitAt(hashStr.length - 1);
      final remainder = charCode % 8;
      num = remainder * 2 + 2;
    } else {
      // 旧算法
      final str = '$epId$pictureName';
      final bytes = utf8.encode(str);
      final hashResult = md5.convert(bytes);
      final hashStr = hashResult.toString();
      final charCode = hashStr.codeUnitAt(hashStr.length - 1);
      final remainder = charCode % 10;
      num = remainder * 2 + 2;
    }

    return num;
  }

  /// 解密图片数据
  /// 将打乱的图片块按正确顺序重新拼接
  /// [imageData] 原始图片数据
  /// [epId] 章节ID
  /// [imageUrl] 图片URL
  /// 返回解密后的图片数据
  static Future<Uint8List> decodeImage(
    Uint8List imageData,
    int epId,
    String imageUrl,
  ) async {
    // GIF 图片不需要解密
    if (imageUrl.toLowerCase().endsWith('.gif')) {
      return imageData;
    }

    final num = calculateSegmentCount(epId, imageUrl);
    
    // num <= 1 表示不需要解密
    if (num <= 1) {
      return imageData;
    }

    // 解码原始图片
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final width = image.width;
    final height = image.height;

    // 计算每个块的大小
    final blockSize = height ~/ num;
    final remainder = height % num;

    // 创建块信息列表
    final blocks = <_ImageBlock>[];
    for (int i = 0; i < num; i++) {
      final start = i * blockSize;
      final end = start + blockSize + (i != num - 1 ? 0 : remainder);
      blocks.add(_ImageBlock(start: start, end: end));
    }

    // 创建新图片，按反向顺序拼接块
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    int y = 0;
    for (int i = blocks.length - 1; i >= 0; i--) {
      final block = blocks[i];
      final currentHeight = block.end - block.start;

      // 从原图中裁剪块并绘制到新位置
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, block.start.toDouble(), width.toDouble(), currentHeight.toDouble()),
        ui.Rect.fromLTWH(0, y.toDouble(), width.toDouble(), currentHeight.toDouble()),
        ui.Paint(),
      );

      y += currentHeight;
    }

    final picture = recorder.endRecording();
    final newImage = await picture.toImage(width, height);

    // 将新图片编码为 PNG
    final byteData = await newImage.toByteData(format: ui.ImageByteFormat.png);
    
    // 清理资源
    image.dispose();
    newImage.dispose();

    if (byteData == null) {
      throw Exception('Failed to encode decoded image');
    }

    return byteData.buffer.asUint8List();
  }

  /// 从URL中提取章节ID
  /// JM图片URL格式: https://xxx/media/photos/{epId}/{imageName}
  static int? extractEpIdFromUrl(String imageUrl) {
    final regex = RegExp(r'/photos/(\d+)/');
    final match = regex.firstMatch(imageUrl);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }
}

class _ImageBlock {
  final int start;
  final int end;

  _ImageBlock({required this.start, required this.end});
}
