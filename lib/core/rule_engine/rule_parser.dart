import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import '../models/unified_rule.dart';
import '../utils/logger.dart';

/// 统一规则解析器
class RuleParser {
  static final RuleParser _instance = RuleParser._internal();
  factory RuleParser() => _instance;
  RuleParser._internal();

  /// 初始化解析器
  Future<void> initCompiler() async {
    try {
      Logger.info('Rule parser initialized');
    } catch (e) {
      Logger.error('Failed to initialize parser: $e');
    }
  }

  /// 释放资源
  void dispose() {
    // 清理资源
  }

  /// 扫描规则目录并解析所有规则
  Future<List<UnifiedRule>> scanAndParseRules(String rulesDir) async {
    final List<UnifiedRule> rules = [];
    
    try {
      final animeDir = Directory(path.join(rulesDir, 'anime'));
      final mangaDir = Directory(path.join(rulesDir, 'manga'));

      // 解析动漫规则 (JSON)
      if (await animeDir.exists()) {
        await for (final file in animeDir.list()) {
          if (file is File && file.path.endsWith('.json')) {
            try {
              final rule = await parseJsonRule(file.path);
              if (rule != null) {
                rules.add(rule);
                Logger.info('Parsed anime rule: ${rule.name}');
              }
            } catch (e) {
              Logger.error('Failed to parse anime rule ${file.path}: $e');
            }
          }
        }
      }

      // 解析漫画规则 (JS)
      if (await mangaDir.exists()) {
        await for (final file in mangaDir.list()) {
          if (file is File && file.path.endsWith('.js')) {
            try {
              final rule = await parseJsRule(file.path);
              if (rule != null) {
                rules.add(rule);
                Logger.info('Parsed manga rule: ${rule.name}');
              }
            } catch (e) {
              Logger.error('Failed to parse manga rule ${file.path}: $e');
            }
          } else if (file is File && file.path.endsWith('.json')) {
            try {
              final rule = await parseJsonRule(file.path);
              if (rule != null) {
                rules.add(rule);
                Logger.info('Parsed manga rule: ${rule.name}');
              }
            } catch (e) {
              Logger.error('Failed to parse manga rule ${file.path}: $e');
            }
          }
        }
      }

      Logger.info('Parsed ${rules.length} rules total');
    } catch (e) {
      Logger.error('Failed to scan rules directory: $e');
    }

    return rules;
  }

  /// 解析JSON规则文件 (Kazumi格式)
  Future<UnifiedRule?> parseJsonRule(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logger.warning('Rule file not found: $filePath');
        return null;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // 验证必要字段
      if (!json.containsKey('name') || !json.containsKey('baseURL')) {
        Logger.warning('Invalid JSON rule format: $filePath');
        return null;
      }

      final t = json['type']?.toString().toLowerCase();
      if (t == 'manga') {
        return UnifiedRule.fromVeneraJson(json, filePath);
      }
      return UnifiedRule.fromKazumiJson(json, filePath);
    } catch (e) {
      Logger.error('Failed to parse JSON rule $filePath: $e');
      return null;
    }
  }

  /// 解析JS规则文件 (Venera格式) - 暂时简化实现
  Future<UnifiedRule?> parseJsRule(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logger.warning('Rule file not found: $filePath');
        return null;
      }

      final content = await file.readAsString();
      
      // 验证JS文件格式
      if (!content.contains('extends ComicSource')) {
        Logger.warning('Invalid JS rule format: $filePath');
        return null;
      }

      // 提取类名
      final classNameMatch = RegExp(r'class\s+(\w+)\s+extends\s+ComicSource')
          .firstMatch(content);
      if (classNameMatch == null) {
        Logger.warning('Cannot find class name in JS rule: $filePath');
        return null;
      }

      final className = classNameMatch.group(1)!;

      // 简单的正则提取元数据（暂时不执行JS代码）
      final nameMatch = RegExp(r'name\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final versionMatch = RegExp(r'version\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final keyMatch = RegExp(r'key\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
      final baseUrlMatch = RegExp(r'baseUrl[^{]*\{\s*return\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);

      final metadata = {
        'key': keyMatch?.group(1) ?? className.toLowerCase(),
        'name': nameMatch?.group(1) ?? className,
        'version': versionMatch?.group(1) ?? '1.0.0',
        'baseUrl': baseUrlMatch?.group(1) ?? '',
      };

      return UnifiedRule.fromVeneraJs(metadata, filePath);
    } catch (e) {
      Logger.error('Failed to parse JS rule $filePath: $e');
      return null;
    }
  }

  /// 重新解析单个规则文件
  Future<UnifiedRule?> reparseRule(String filePath) async {
    if (filePath.endsWith('.json')) {
      return await parseJsonRule(filePath);
    } else if (filePath.endsWith('.js')) {
      return await parseJsRule(filePath);
    } else {
      Logger.warning('Unsupported rule file format: $filePath');
      return null;
    }
  }

  /// 验证规则文件格式
  Future<bool> validateRuleFile(String filePath) async {
    try {
      final rule = await reparseRule(filePath);
      return rule != null;
    } catch (e) {
      Logger.error('Rule validation failed for $filePath: $e');
      return false;
    }
  }

  /// 获取规则文件的基本信息（不完全解析）
  Future<Map<String, dynamic>?> getRuleInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      if (filePath.endsWith('.json')) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final t = json['type']?.toString().toLowerCase();
        return {
          'name': json['name'] ?? 'Unknown',
          'version': json['version'] ?? '1.0.0',
          'type': t == 'manga' ? 'manga' : 'anime',
          'baseUrl': json['baseURL'] ?? '',
        };
      } else if (filePath.endsWith('.js')) {
        final content = await file.readAsString();
        
        // 简单的正则提取（不执行JS）
        final nameMatch = RegExp(r'name\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
        final versionMatch = RegExp(r'version\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
        final keyMatch = RegExp(r'key\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(content);
        
        return {
          'name': nameMatch?.group(1) ?? 'Unknown',
          'version': versionMatch?.group(1) ?? '1.0.0',
          'key': keyMatch?.group(1) ?? 'unknown',
          'type': 'manga',
        };
      }
    } catch (e) {
      Logger.error('Failed to get rule info for $filePath: $e');
    }
    
    return null;
  }
}