import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'anime_store.dart';
import 'widgets/anime_search_bar.dart';
import 'widgets/anime_search_results.dart';
import 'widgets/anime_detail_view.dart';
import 'widgets/html_content_dialog.dart';

/// 动漫页面
class AnimePage extends StatefulWidget {
  final String? ruleKey;
  
  const AnimePage({super.key, this.ruleKey});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  final AnimeStore store = Modular.get<AnimeStore>();

  @override
  void initState() {
    super.initState();
    // 传递规则key给store
    _initializeWithRule();
  }

  @override
  void didUpdateWidget(AnimePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 ruleKey 改变时重新初始化
    if (oldWidget.ruleKey != widget.ruleKey) {
      _initializeWithRule();
    }
  }

  void _initializeWithRule() {
    store.initialize(widget.ruleKey);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 显示当前规则信息
              if (store.selectedRule != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.source,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.selectedRule!.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '动漫源 • v${store.selectedRule!.version}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // 搜索栏
              AnimeSearchBar(store: store),
              const SizedBox(height: 16),
              
              // 主内容区域
              Expanded(
                child: _buildMainContent(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Observer(
      builder: (context) {
        if (store.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    store.error!,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () {
                        store.clearSearchResults();
                        if (store.searchKeyword.isNotEmpty) {
                          store.searchAnime();
                        }
                      },
                      child: const Text('重试'),
                    ),
                    if (store.htmlContent != null) ...[
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () => _showHtmlContent(context),
                        icon: const Icon(Icons.code),
                        label: const Text('查看HTML'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        }

        if (store.currentAnimeDetail != null) {
          return AnimeDetailView(
            detail: store.currentAnimeDetail!,
            store: store,
          );
        }

        if (store.searchResults.isNotEmpty) {
          return AnimeSearchResults(store: store);
        }

        if (store.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('搜索中...'),
              ],
            ),
          );
        }

        // 如果有搜索关键词但没有结果，显示无结果状态
        if (store.searchKeyword.isNotEmpty && store.searchResults.isEmpty && store.error == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '没有找到相关结果',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '尝试使用不同的关键词或更换规则源',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    store.clearSearchResults();
                  },
                  child: const Text('重新搜索'),
                ),
              ],
            ),
          );
        }

        // 默认状态 - 显示欢迎信息
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '搜索你喜欢的动漫',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '选择规则源并输入关键词开始搜索',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHtmlContent(BuildContext context) {
    if (store.htmlContent != null) {
      showDialog(
        context: context,
        builder: (context) => HtmlContentDialog(
          htmlContent: store.htmlContent!,
          title: '搜索页面HTML内容 - ${store.selectedRule?.name ?? "未知规则"}',
        ),
      );
    }
  }
}