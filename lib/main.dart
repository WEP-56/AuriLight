import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

// Platform-specific WebView imports
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'app_module.dart';
import 'app_widget.dart';
import 'core/storage/storage.dart';
import 'core/services/kazumi_network_service.dart';
import 'core/services/webview_environment_manager.dart';
import 'core/services/favorite_service.dart';
import 'core/utils/logger.dart';
import 'features/manga/manga_module.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 隐藏原生标题栏
      windowButtonVisibility: false,
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  // Initialize MediaKit for video playback
  MediaKit.ensureInitialized();
  
  // Initialize WebView platforms
  try {
    Logger.info('Initializing WebView platforms...');
    
    if (Platform.isAndroid) {
      // Initialize Android WebView
      AndroidWebViewController.enableDebugging(true);
      Logger.info('Android WebView platform initialized');
    } else if (Platform.isIOS) {
      // iOS WebView is automatically initialized
      Logger.info('iOS WebView platform initialized');
    } else if (Platform.isWindows) {
      // Windows WebView (webview_windows for video parsing)
      Logger.info('Windows WebView platform initialization');
      await WebViewEnvironmentManager.ensureInitialized();
    }
    
    Logger.info('WebView platforms initialized successfully');
  } catch (e) {
    Logger.warning('WebView platform initialization failed: $e');
    // Continue - we'll handle this gracefully in the network service
  }
  
  // Setup system UI
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }
  
  try {
    // Initialize Hive database (simplified)
    await Hive.initFlutter('kazuvera2d');
    await AppStorage.init();
    
    // Initialize network service
    KazumiNetworkService().initialize();
    
    // Initialize manga module
    await MangaModuleInitializer.initialize();
    
    // Initialize favorite service
    await FavoriteService().init();
    
    Logger.info('AuriLight initialized successfully');
    
    runApp(ModularApp(module: AppModule(), child: const AppWidget()));
  } catch (e) {
    Logger.error('Failed to initialize app: $e');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Failed to initialize app: $e'),
            ],
          ),
        ),
      ),
    ));
  }
}