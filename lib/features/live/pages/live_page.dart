/// Live streaming page
/// Main page for live streaming functionality
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:simple_live_core/simple_live_core.dart';
import '../../../core/services/live_manager.dart';
import '../widgets/live_search_bar.dart';
import '../widgets/live_search_results.dart';
import 'live_player_page.dart';

class LivePage extends StatefulWidget {
  final String platformId;
  final Function(String) onPlatformChanged;

  const LivePage({
    super.key,
    required this.platformId,
    required this.onPlatformChanged,
  });

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  List<LiveRoomItem> _searchResults = [];
  List<LiveRoomItem> _recommendResults = [];
  List<LiveCategory> _categories = [];
  
  bool _isSearching = false;
  bool _isLoadingRecommend = false;
  bool _isLoadingCategories = false;
  
  String _searchKeyword = '';
  int _searchPage = 1;
  int _recommendPage = 1;
  bool _hasMoreSearch = false;
  bool _hasMoreRecommend = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platformId != widget.platformId) {
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadRecommendRooms(reset: true),
      _loadCategories(),
    ]);
  }

  Future<void> _loadRecommendRooms({bool reset = true}) async {
    if (_isLoadingRecommend) return;
    
    setState(() => _isLoadingRecommend = true);

    try {
      final page = reset ? 1 : _recommendPage + 1;
      final result = await LiveManager().getRecommendRooms(page: page);
      
      setState(() {
        _recommendPage = page;
        _hasMoreRecommend = result.hasMore;
        if (reset) {
          _recommendResults = result.items;
        } else {
          _recommendResults.addAll(result.items);
        }
      });
    } catch (e) {
      debugPrint('加载推荐直播间失败: $e');
    } finally {
      if (mounted) setState(() => _isLoadingRecommend = false);
    }
  }

  Future<void> _loadCategories() async {
    if (_isLoadingCategories) return;
    
    setState(() => _isLoadingCategories = true);

    try {
      final categories = await LiveManager().getCategories();
      setState(() => _categories = categories);
    } catch (e) {
      debugPrint('加载直播分类失败: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _searchRooms({bool reset = true}) async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    if (_isSearching && !reset) return;

    setState(() => _isSearching = true);

    try {
      final page = reset ? 1 : _searchPage + 1;
      final result = await LiveManager().searchRooms(keyword, page: page);
      
      setState(() {
        _searchKeyword = keyword;
        _searchPage = page;
        _hasMoreSearch = result.hasMore;
        if (reset) {
          _searchResults = result.items;
        } else {
          _searchResults.addAll(result.items);
        }
      });
    } catch (e) {
      debugPrint('搜索直播间失败: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onRoomTap(LiveRoomItem room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LivePlayerPage(room: room),
      ),
    );
  }

  void _showLoginDialog() {
    final currentSite = LiveManager().getSite(widget.platformId);
    final supportsLogin = LiveManager().supportsCookieLogin(widget.platformId);
    
    if (!supportsLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${currentSite?.name ?? '该平台'}暂不支持登录')),
      );
      return;
    }
    
    // B站使用二维码登录
    if (widget.platformId == 'bilibili') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => BilibiliQRLoginPage(
            onLoginSuccess: () {
              _loadInitialData();
            },
          ),
        ),
      );
      return;
    }
    
    // 其他平台使用Cookie登录
    final isLoggedIn = LiveManager().isLoggedIn(widget.platformId);
    final cookieController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${currentSite?.name ?? '平台'}登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isLoggedIn ? '当前状态: 已登录' : '当前状态: 未登录'),
            const SizedBox(height: 16),
            const Text('请输入Cookie进行登录:'),
            const SizedBox(height: 8),
            TextField(
              controller: cookieController,
              decoration: const InputDecoration(
                hintText: '粘贴Cookie',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          if (isLoggedIn)
            TextButton(
              onPressed: () {
                LiveManager().setCookie(widget.platformId, '');
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已退出登录')),
                );
              },
              child: const Text('退出登录'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (cookieController.text.isNotEmpty) {
                LiveManager().setCookie(widget.platformId, cookieController.text);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cookie已保存')),
                );
                _loadInitialData();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSite = LiveManager().getSite(widget.platformId);
    final supportsLogin = widget.platformId == 'bilibili' || widget.platformId == 'douyin';
    final isLoggedIn = LiveManager().isLoggedIn(widget.platformId);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(currentSite?.name ?? '直播'),
        actions: [
          if (supportsLogin)
            IconButton(
              onPressed: _showLoginDialog,
              icon: Icon(
                isLoggedIn ? Icons.person : Icons.person_outline,
                color: isLoggedIn ? Colors.green : null,
              ),
              tooltip: isLoggedIn ? '已登录' : '登录',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '搜索', icon: Icon(Icons.search)),
            Tab(text: '推荐', icon: Icon(Icons.recommend)),
            Tab(text: '分类', icon: Icon(Icons.category)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 搜索页面
          Column(
            children: [
              LiveSearchBar(
                controller: _searchController,
                onSearch: () => _searchRooms(reset: true),
                isLoading: _isSearching,
              ),
              Expanded(
                child: LiveSearchResults(
                  results: _searchResults,
                  isLoading: _isSearching,
                  hasMore: _hasMoreSearch,
                  onLoadMore: () => _searchRooms(reset: false),
                  onRoomTap: _onRoomTap,
                  emptyMessage: _searchKeyword.isEmpty 
                      ? '请输入关键词搜索直播间' 
                      : '未找到相关直播间',
                ),
              ),
            ],
          ),
          
          // 推荐页面
          LiveSearchResults(
            results: _recommendResults,
            isLoading: _isLoadingRecommend,
            hasMore: _hasMoreRecommend,
            onLoadMore: () => _loadRecommendRooms(reset: false),
            onRoomTap: _onRoomTap,
            emptyMessage: '暂无推荐直播间',
          ),
          
          // 分类页面
          _buildCategoriesView(),
        ],
      ),
    );
  }

  Widget _buildCategoriesView() {
    if (_isLoadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('暂无分类信息'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: _buildCategoryIcon(),
            title: Text(category.name),
            subtitle: Text('${category.children.length} 个子分类'),
            children: category.children.map((subCategory) {
              return ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(subCategory.name),
                onTap: () => _openCategoryRooms(subCategory),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildCategoryIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.category, color: Colors.grey),
    );
  }

  void _openCategoryRooms(LiveSubCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CategoryRoomsPage(
          category: category,
          onRoomTap: _onRoomTap,
        ),
      ),
    );
  }
}

/// 分类直播间列表页面
class CategoryRoomsPage extends StatefulWidget {
  final LiveSubCategory category;
  final Function(LiveRoomItem) onRoomTap;

  const CategoryRoomsPage({
    super.key,
    required this.category,
    required this.onRoomTap,
  });

  @override
  State<CategoryRoomsPage> createState() => _CategoryRoomsPageState();
}

class _CategoryRoomsPageState extends State<CategoryRoomsPage> {
  List<LiveRoomItem> _rooms = [];
  bool _isLoading = false;
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadRooms(reset: true);
  }

  Future<void> _loadRooms({bool reset = true}) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);

    try {
      final page = reset ? 1 : _page + 1;
      final result = await LiveManager().getCategoryRooms(widget.category, page: page);
      
      setState(() {
        _page = page;
        _hasMore = result.hasMore;
        if (reset) {
          _rooms = result.items;
        } else {
          _rooms.addAll(result.items);
        }
      });
    } catch (e) {
      debugPrint('加载分类直播间失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: LiveSearchResults(
        results: _rooms,
        isLoading: _isLoading,
        hasMore: _hasMore,
        onLoadMore: () => _loadRooms(reset: false),
        onRoomTap: widget.onRoomTap,
        emptyMessage: '暂无直播间',
      ),
    );
  }
}

/// B站登录页面 - 支持扫码和Cookie两种登录方式
class BilibiliQRLoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const BilibiliQRLoginPage({super.key, required this.onLoginSuccess});

  @override
  State<BilibiliQRLoginPage> createState() => _BilibiliQRLoginPageState();
}

class _BilibiliQRLoginPageState extends State<BilibiliQRLoginPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 扫码登录相关
  String? _qrUrl;
  String? _qrKey;
  String _qrStatus = '正在获取二维码...';
  Timer? _pollTimer;
  bool _isQrLoading = true;
  
  // Cookie登录相关
  final TextEditingController _cookieController = TextEditingController();
  bool _isCookieLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _getQRCode();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _getQRCode() async {
    setState(() {
      _isQrLoading = true;
      _qrStatus = '正在获取二维码...';
    });
    
    try {
      final response = await http.get(
        Uri.parse('https://passport.bilibili.com/x/passport-login/web/qrcode/generate'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.bilibili.com/',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          setState(() {
            _qrUrl = data['data']['url'];
            _qrKey = data['data']['qrcode_key'];
            _qrStatus = '请使用哔哩哔哩APP扫描二维码';
            _isQrLoading = false;
          });
          _startPolling();
        } else {
          setState(() {
            _qrStatus = '获取二维码失败: ${data['message']}';
            _isQrLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _qrStatus = '获取二维码失败: $e';
        _isQrLoading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkLoginStatus());
  }

  Future<void> _checkLoginStatus() async {
    if (_qrKey == null || !mounted) return;

    try {
      // 使用 http 包发送请求，它会自动处理 set-cookie
      final response = await http.get(
        Uri.parse('https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=$_qrKey'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.bilibili.com/',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final code = data['data']['code'];
        
        switch (code) {
          case 0: // 登录成功
            _pollTimer?.cancel();
            
            // 方法1: 从响应头的 set-cookie 中提取 cookie
            final setCookieHeaders = response.headers['set-cookie'];
            List<String> cookies = [];
            
            if (setCookieHeaders != null && setCookieHeaders.isNotEmpty) {
              // set-cookie 可能是多个 cookie 用逗号分隔
              final cookieParts = setCookieHeaders.split(RegExp(r',(?=[^;]*=)'));
              for (final part in cookieParts) {
                final cookie = part.split(';')[0].trim();
                if (cookie.isNotEmpty && cookie.contains('=')) {
                  cookies.add(cookie);
                }
              }
            }
            
            // 方法2: 如果响应头没有 cookie，从 URL 参数中提取（备用方案）
            if (cookies.isEmpty) {
              final url = data['data']['url'];
              if (url != null) {
                final uri = Uri.parse(url);
                uri.queryParameters.forEach((key, value) {
                  if (key == 'DedeUserID' || key == 'DedeUserID__ckMd5' || 
                      key == 'SESSDATA' || key == 'bili_jct') {
                    cookies.add('$key=$value');
                  }
                });
              }
            }
            
            if (cookies.isNotEmpty) {
              final cookieStr = cookies.join('; ');
              debugPrint('[B站登录] 获取到Cookie: ${cookieStr.substring(0, cookieStr.length.clamp(0, 50))}...');
              await LiveManager().setCookie('bilibili', cookieStr);
            }
            
            if (mounted) {
              setState(() => _qrStatus = '登录成功！');
              await Future.delayed(const Duration(seconds: 1));
              widget.onLoginSuccess();
              if (mounted) Navigator.of(context).pop();
            }
            break;
          case 86038: // 二维码已失效
            _pollTimer?.cancel();
            if (mounted) setState(() => _qrStatus = '二维码已失效，请刷新');
            break;
          case 86090: // 已扫码未确认
            if (mounted) setState(() => _qrStatus = '已扫码，请在APP上确认');
            break;
          case 86101: // 未扫码
            // 继续轮询
            break;
        }
      }
    } catch (e) {
      debugPrint('检查登录状态失败: $e');
    }
  }

  Future<void> _loginWithCookie() async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入Cookie')),
      );
      return;
    }
    
    setState(() => _isCookieLoading = true);
    
    try {
      // 验证 Cookie 是否有效
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/member/web/account'),
        headers: {
          'Cookie': cookie,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.bilibili.com/',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 0) {
          // Cookie 有效，保存并返回
          await LiveManager().setCookie('bilibili', cookie);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('登录成功！欢迎 ${data['data']['uname'] ?? '用户'}')),
            );
            widget.onLoginSuccess();
            Navigator.of(context).pop();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cookie无效: ${data['message']}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCookieLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = LiveManager().isLoggedIn('bilibili');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('哔哩哔哩登录'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '扫码登录', icon: Icon(Icons.qr_code)),
            Tab(text: 'Cookie登录', icon: Icon(Icons.cookie)),
          ],
        ),
        actions: [
          if (isLoggedIn)
            TextButton(
              onPressed: () async {
                await LiveManager().setCookie('bilibili', '');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已退出登录')),
                  );
                  Navigator.of(context).pop();
                }
              },
              child: const Text('退出登录', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 扫码登录页面
          _buildQRLoginView(),
          // Cookie登录页面
          _buildCookieLoginView(),
        ],
      ),
    );
  }

  Widget _buildQRLoginView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isQrLoading)
              const CircularProgressIndicator()
            else if (_qrUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.network(
                  'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(_qrUrl!)}',
                  width: 200,
                  height: 200,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: Text('二维码加载失败')),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              _qrStatus, 
              style: TextStyle(
                fontSize: 16,
                color: _qrStatus.contains('成功') ? Colors.green : null,
              ),
            ),
            const SizedBox(height: 16),
            if (!_isQrLoading && (_qrUrl == null || _qrStatus.contains('失效')))
              ElevatedButton.icon(
                onPressed: _getQRCode,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新二维码'),
              ),
            const SizedBox(height: 32),
            const Text(
              '使用说明：\n1. 打开哔哩哔哩APP\n2. 点击右上角扫一扫\n3. 扫描上方二维码\n4. 在APP上确认登录',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCookieLoginView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '手动输入Cookie登录',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cookieController,
            decoration: const InputDecoration(
              hintText: '粘贴Cookie内容',
              border: OutlineInputBorder(),
              helperText: '需要包含 SESSDATA、bili_jct、DedeUserID 等字段',
            ),
            maxLines: 5,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isCookieLoading ? null : _loginWithCookie,
            child: _isCookieLoading 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('验证并登录'),
          ),
          const SizedBox(height: 32),
          const Text(
            '获取Cookie方法：\n'
            '1. 在浏览器中登录 bilibili.com\n'
            '2. 按 F12 打开开发者工具\n'
            '3. 切换到 Network（网络）标签\n'
            '4. 刷新页面，点击任意请求\n'
            '5. 在 Headers 中找到 Cookie 字段\n'
            '6. 复制完整的 Cookie 值粘贴到上方',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
