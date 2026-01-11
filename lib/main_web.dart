import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('AuriLight Web Version Started');
  
  runApp(ModularApp(module: WebAppModule(), child: const WebApp()));
}

class WebAppModule extends Module {
  @override
  void routes(r) {
    r.child('/', child: (context) => const HomePage());
  }
}

class WebApp extends StatelessWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AuriLight - Web版',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      routerConfig: Modular.routerConfig,
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;
  bool isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // 应用标题栏
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_filled,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'AuriLight',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // 主题切换按钮
                      IconButton(
                        onPressed: () {
                          setState(() {
                            isDarkMode = !isDarkMode;
                          });
                        },
                        icon: Icon(
                          isDarkMode ? Icons.light_mode : Icons.dark_mode,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 导航菜单
                Expanded(
                  child: ListView(
                    children: [
                      _buildNavItem(0, Icons.home, '首页'),
                      _buildNavItem(1, Icons.favorite, '收藏'),
                      _buildNavItem(2, Icons.download, '下载'),
                      _buildNavItem(3, Icons.history, '历史'),
                      _buildNavItem(4, Icons.settings, '设置'),
                      
                      const Divider(),
                      
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.source, size: 20),
                            SizedBox(width: 8),
                            Text(
                              '规则源',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            Spacer(),
                            Chip(
                              label: Text('2', style: TextStyle(fontSize: 12)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
                      ),
                      
                      _buildRuleItem('示例动漫源', '动漫', Icons.play_arrow, Colors.blue, true),
                      _buildRuleItem('示例漫画源', '漫画', Icons.book, Colors.green, true),
                    ],
                  ),
                ),
                
                // 底部操作按钮
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddRuleDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('添加规则源'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => _showSnackBar('刷新规则功能开发中...'),
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新规则'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 分割线
          const VerticalDivider(width: 1),
          
          // 主内容区域
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected 
          ? Theme.of(context).colorScheme.primary 
          : Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected 
            ? Theme.of(context).colorScheme.primary 
            : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      onTap: () => setState(() => selectedIndex = index),
      dense: true,
    );
  }

  Widget _buildRuleItem(String name, String type, IconData icon, Color color, bool enabled) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(name, style: const TextStyle(fontSize: 14)),
        subtitle: Text(type, style: const TextStyle(fontSize: 12)),
        trailing: Switch(
          value: enabled,
          onChanged: (value) => _showSnackBar('${value ? "启用" : "禁用"}了 $name'),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onTap: () => _showSnackBar('点击了 $name'),
        dense: true,
      ),
    );
  }

  Widget _buildMainContent() {
    switch (selectedIndex) {
      case 0:
        return _buildHomePage();
      case 1:
        return _buildPage('收藏', Icons.favorite, '收藏功能开发中...');
      case 2:
        return _buildPage('下载', Icons.download, '下载功能开发中...');
      case 3:
        return _buildPage('历史', Icons.history, '历史功能开发中...');
      case 4:
        return _buildPage('设置', Icons.settings, '设置功能开发中...');
      default:
        return _buildHomePage();
    }
  }

  Widget _buildHomePage() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '欢迎使用 AuriLight',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            '统一的动漫和漫画观看平台 - Web版演示',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 功能演示区域
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 800 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildFeatureCard(
                      title: '动漫源',
                      count: '1',
                      icon: Icons.play_arrow,
                      color: Colors.blue,
                      description: '支持多种动漫源\nKazumi JSON 规则',
                    ),
                    _buildFeatureCard(
                      title: '漫画源',
                      count: '1',
                      icon: Icons.book,
                      color: Colors.green,
                      description: '支持多种漫画源\nVenera JS 规则',
                    ),
                    _buildFeatureCard(
                      title: '统一规则',
                      count: '✓',
                      icon: Icons.rule,
                      color: Colors.orange,
                      description: 'JSON + JS 规则\n统一管理系统',
                    ),
                    _buildFeatureCard(
                      title: '热插拔',
                      count: '✓',
                      icon: Icons.swap_horiz,
                      color: Colors.purple,
                      description: '动态源管理\n拖拽排序支持',
                    ),
                  ],
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          Center(
            child: Column(
              children: [
                Text(
                  'AuriLight v1.0.0 - Web版本运行成功！',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '基础界面框架已完成',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(String title, IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(message),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _showSnackBar('$title 功能即将推出！'),
                    child: const Text('了解更多'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required String description,
  }) {
    return Card(
      child: InkWell(
        onTap: () => _showSnackBar('点击了 $title 功能卡片'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                count,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRuleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加规则源'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('请选择添加方式：'),
            SizedBox(height: 16),
            Text(
              '• 从文件导入规则\n'
              '• 从URL下载规则\n'
              '• 扫描规则目录',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showSnackBar('从文件导入功能开发中...');
            },
            child: const Text('从文件导入'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}