import 'dart:developer' as developer;

/// 日志级别枚举
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 简单的日志工具类
class Logger {
  static const String _tag = 'AuriLight';
  
  /// 信息日志
  static void info(String message) {
    developer.log(message, name: _tag, level: 800);
  }
  
  /// 警告日志
  static void warning(String message) {
    developer.log(message, name: _tag, level: 900);
  }
  
  /// 错误日志
  static void error(String message) {
    developer.log(message, name: _tag, level: 1000);
  }
  
  /// 调试日志
  static void debug(String message) {
    developer.log(message, name: _tag, level: 700);
  }

  /// 添加日志（支持不同级别）
  static void addLog(LogLevel level, String tag, String message) {
    final fullMessage = '[$tag] $message';
    switch (level) {
      case LogLevel.debug:
        debug(fullMessage);
        break;
      case LogLevel.info:
        info(fullMessage);
        break;
      case LogLevel.warning:
        warning(fullMessage);
        break;
      case LogLevel.error:
        error(fullMessage);
        break;
    }
  }
}