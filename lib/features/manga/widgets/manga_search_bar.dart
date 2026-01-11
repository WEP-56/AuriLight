import 'package:flutter/material.dart';

/// 漫画搜索栏 - 简化版，移除规则源选择
class MangaSearchBar extends StatefulWidget {
  final Function(String) onSearch;
  final bool isSearching;
  final String? currentRuleName;
  final bool hasAccount;
  final bool isLoggedIn;
  final Future<bool> Function(String username, String password)? onLogin;
  final Future<bool> Function()? onReLogin;
  final Future<void> Function()? onLogout;

  const MangaSearchBar({
    super.key,
    required this.onSearch,
    required this.isSearching,
    this.currentRuleName,
    this.hasAccount = false,
    this.isLoggedIn = false,
    this.onLogin,
    this.onReLogin,
    this.onLogout,
  });

  @override
  State<MangaSearchBar> createState() => _MangaSearchBarState();
}

class _MangaSearchBarState extends State<MangaSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isExpanded = false;

  Future<void> _showLoginDialog() async {
    if (widget.onLogin == null) return;
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('登录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: '账号'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('登录'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await widget.onLogin!(username, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '登录成功' : '登录失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录出错: $e')),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }


  Future<void> _reLogin() async {
    if (widget.onReLogin == null) return;
    
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await widget.onReLogin!();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? '重登成功' : '重登失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重登出错: $e')),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _logout() async {
    if (widget.onLogout == null) return;
    
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await widget.onLogout!();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('退出出错: $e')),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final keyword = _searchController.text.trim();
    print('[搜索栏] 执行搜索: $keyword');
    if (keyword.isNotEmpty) {
      widget.onSearch(keyword);
      _searchFocusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUseAccount = widget.currentRuleName != null && widget.hasAccount;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.currentRuleName != null)
                  Row(
                    children: [
                      Icon(
                        Icons.source,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '规则源: ${widget.currentRuleName}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        tooltip: '更多选项',
                      ),
                    ],
                  ),
                
                if (widget.currentRuleName != null) const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: widget.currentRuleName != null ? '输入关键词...' : '请先选择规则源',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: widget.isSearching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabled: widget.currentRuleName != null && !widget.isSearching,
                        ),
                        enabled: widget.currentRuleName != null && !widget.isSearching,
                        onSubmitted: (value) {
                          print('[搜索栏] 回车提交，准备搜索: $value');
                          _performSearch();
                        },
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: widget.currentRuleName != null && 
                                 !widget.isSearching && 
                                 _searchController.text.trim().isNotEmpty
                          ? () {
                              print('[搜索栏] 按钮点击，准备搜索: ${_searchController.text.trim()}');
                              _performSearch();
                            }
                          : null,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          if (_isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    '更多功能',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      const Icon(Icons.verified_user, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        widget.isLoggedIn ? '已登录' : '未登录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: widget.isLoggedIn
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: canUseAccount ? _showLoginDialog : null,
                        icon: const Icon(Icons.login, size: 16),
                        label: const Text('登录'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),

                      OutlinedButton.icon(
                        onPressed: canUseAccount ? _reLogin : null,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重登'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),

                      OutlinedButton.icon(
                        onPressed: canUseAccount ? _logout : null,
                        icon: const Icon(Icons.logout, size: 16),
                        label: const Text('退出'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('设置'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}
