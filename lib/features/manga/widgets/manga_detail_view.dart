import 'package:flutter/material.dart';
import '../../../core/models/manga_item.dart';
import '../../../core/services/manga_image_provider.dart';

/// 漫画详情页面 
class MangaDetailView extends StatefulWidget {
  final MangaDetail? detail;
  final bool isLoading;
  final VoidCallback onBack;
  final Function(String) onReadChapter;
  final VoidCallback onToggleFavorite;
  final bool isFavorite;
  final bool hasAccount;
  final Future<bool> Function(String username, String password)? onLogin;
  final Future<bool> Function()? onReLogin;
  final Future<void> Function()? onLogout;
  final Map<String, String>? headers;
  final String? referer;
  final List<String>? cdnFallbacks;
  final bool forceWebView;

  const MangaDetailView({
    super.key,
    required this.detail,
    required this.isLoading,
    required this.onBack,
    required this.onReadChapter,
    required this.onToggleFavorite,
    this.isFavorite = false,
    this.hasAccount = false,
    this.onLogin,
    this.onReLogin,
    this.onLogout,
    this.headers,
    this.referer,
    this.cdnFallbacks,
    this.forceWebView = false,
  });

  @override
  State<MangaDetailView> createState() => _MangaDetailViewState();
}

class _MangaDetailViewState extends State<MangaDetailView> {
  final ScrollController _scrollController = ScrollController();

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

  Future<void> _doReLogin() async {
    if (widget.onReLogin == null) return;
    final loading = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final ok = await widget.onReLogin!();
    if (mounted) {
      Navigator.of(context).pop();
    }
    await loading;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '重登成功' : '重登失败')),
    );
  }

  Future<void> _doLogout() async {
    if (widget.onLogout == null) return;
    await widget.onLogout!();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('加载中...'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (widget.detail == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('详情'),
        ),
        body: const Center(
          child: Text('加载失败'),
        ),
      );
    }

    final detail = widget.detail!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          detail.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.hasAccount)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'login') {
                  _showLoginDialog();
                } else if (value == 'relogin') {
                  _doReLogin();
                } else if (value == 'logout') {
                  _doLogout();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'login', child: Text('登录')),
                PopupMenuItem(value: 'relogin', child: Text('重登')),
                PopupMenuItem(value: 'logout', child: Text('退出登录')),
              ],
            ),
        ],
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 漫画基本信息区域
            _buildHeaderSection(detail),

            // 操作按钮区域
            _buildActionButtons(detail),
            
            // 描述区域
            _buildDescriptionSection(detail),
            
            // 信息标签区域
            _buildInfoSection(detail),
            
            // 章节列表区域
            _buildChapterSection(detail),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(MangaDetail detail) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 漫画封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 160,
              child: detail.cover != null
                  ? Image(
                      image: MangaImageProvider(
                        sourceKey: detail.ruleKey,
                        imageUrl: detail.cover!,
                        headers: widget.headers,
                        referer: widget.referer,
                        cdnFallbacks: widget.cdnFallbacks,
                        forceWebView: widget.forceWebView,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported),
                        );
                      },
                    )
                  : Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported),
                    ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 漫画信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  detail.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                // 副标题
                if (detail.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail.subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                const SizedBox(height: 8),
                
                // 评分
                if (detail.stars != null && detail.stars! > 0) ...[
                  Row(
                    children: [
                      ...List.generate(5, (index) {
                        return Icon(
                          index < detail.stars!.round()
                              ? Icons.star
                              : Icons.star_border,
                          size: 16,
                          color: Colors.amber,
                        );
                      }),
                      const SizedBox(width: 4),
                      Text(
                        detail.stars!.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                
                // 作者
                if (detail.uploader != null) ...[
                  Text(
                    '作者: ${detail.uploader}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                
                // 更新时间
                if (detail.updateTime != null) ...[
                  Text(
                    '更新: ${detail.updateTime}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(MangaDetail detail) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 开始阅读
          Expanded(
            child: FilledButton.icon(
              onPressed: detail.chapterList.isNotEmpty
                  ? () => widget.onReadChapter(detail.chapterList.first.id)
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始'),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // 下载
          OutlinedButton.icon(
            onPressed: () {
              // TODO: 实现下载功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('下载功能开发中')),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('下载'),
          ),
          
          const SizedBox(width: 12),
          
          // 收藏
          OutlinedButton.icon(
            onPressed: widget.onToggleFavorite,
            icon: Icon(
              widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.isFavorite ? Colors.red : null,
            ),
            label: const Text('收藏'),
          ),
          
          const SizedBox(width: 12),
          
          // 评论
          OutlinedButton.icon(
            onPressed: () {
              // TODO: 实现评论功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('评论功能开发中')),
              );
            },
            icon: const Icon(Icons.comment),
            label: const Text('评论'),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(MangaDetail detail) {
    if (detail.description == null || detail.description!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '描述',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail.description!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(MangaDetail detail) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '信息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // 信息项
          if (detail.uploader != null)
            _buildInfoItem('作者', detail.uploader!, Colors.blue),
          
          if (detail.updateTime != null)
            _buildInfoItem('更新', detail.updateTime!, Colors.cyan),
          
          // 标签
          if (detail.tags != null && detail.tags!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildTagsSection(detail.tags!),
          ],
          
          // 状态
          const SizedBox(height: 8),
          _buildInfoItem('状态', '连载中', Colors.pink), // TODO: 从规则获取实际状态
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection(Map<String, List<String>> tags) {
    final allTags = <String>[];
    tags.forEach((category, tagList) {
      allTags.addAll(tagList);
    });

    if (allTags.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '标签',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.purple,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: allTags.take(10).map((tag) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tag,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChapterSection(MangaDetail detail) {
    final chapters = detail.chapterList;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  chapters.isEmpty ? '阅读' : '章节',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '默认',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (chapters.isEmpty)
            // 对于没有章节的漫画（如绅士漫画），显示直接阅读按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // 使用漫画ID作为章节ID
                    widget.onReadChapter(detail.id);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始阅读'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                return ListTile(
                  title: Text(
                    chapter.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onReadChapter(chapter.id),
                );
              },
            ),
        ],
      ),
    );
  }
}