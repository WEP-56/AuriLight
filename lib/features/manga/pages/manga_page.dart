import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:get_it/get_it.dart';

import '../manga_store.dart';
import '../widgets/manga_search_bar.dart';
import '../widgets/manga_search_results.dart';
import '../widgets/manga_detail_view.dart';
import '../widgets/manga_reader.dart';

/// 漫画主页面 - 统一的漫画功能入口
class MangaPage extends StatefulWidget {
  final String? ruleKey; // 接收从侧边栏传递的规则key
  
  const MangaPage({super.key, this.ruleKey});

  @override
  State<MangaPage> createState() => _MangaPageState();
}

class _MangaPageState extends State<MangaPage> {
  late final MangaStore _store;
  String? _currentRuleKey;

  @override
  void initState() {
    super.initState();
    _store = GetIt.instance<MangaStore>();
    _currentRuleKey = widget.ruleKey;
    _initializeStore();
  }

  @override
  void didUpdateWidget(MangaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检查规则key是否发生变化
    if (widget.ruleKey != _currentRuleKey) {
      print('[漫画页面] 规则切换: $_currentRuleKey -> ${widget.ruleKey}');
      _currentRuleKey = widget.ruleKey;
      
      // 如果传递了新的规则key，切换到该规则
      if (widget.ruleKey != null) {
        _store.selectRule(widget.ruleKey!);
        print('[漫画页面] 已选择规则: ${widget.ruleKey}');
      }
    }
  }

  Future<void> _initializeStore() async {
    await _store.initialize();
    
    // 如果传递了规则key，自动选择该规则
    if (widget.ruleKey != null) {
      _store.selectRule(widget.ruleKey!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Observer(
        builder: (context) {
          switch (_store.currentView) {
            case 'detail':
              final isFav = _store.currentDetail != null 
                  ? _store.isFavoritedSync(_store.currentDetail!.ruleKey, _store.currentDetail!.id)
                  : false;
              return MangaDetailView(
                detail: _store.currentDetail,
                isLoading: _store.isLoadingDetail,
                onBack: _store.backToSearch,
                isFavorite: isFav,
                hasAccount: _store.supportsAccountForRule(_store.selectedRuleKey),
                onLogin: (username, password) {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value(false);
                  return _store.login(key, username, password);
                },
                onReLogin: () {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value(false);
                  return _store.reLogin(key);
                },
                onLogout: () {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value();
                  return _store.logout(key);
                },
                headers: _store.getReaderHeadersForRule(_store.selectedRuleKey),
                referer: _store.getReaderRefererForRule(_store.selectedRuleKey),
                cdnFallbacks: _store.getCdnFallbacksForCurrentRule(),
                forceWebView: _store.getUseWebviewForRule(_store.selectedRuleKey),
                onReadChapter: (chapterId) {
                  if (_store.currentDetail != null) {
                    _store.loadChapter(
                      _store.currentDetail!.ruleKey,
                      _store.currentDetail!.id,
                      chapterId,
                    );
                  }
                },
                onToggleFavorite: () async {
                  if (_store.currentDetail != null) {
                    final isFav = await _store.toggleFavorite(_store.currentDetail!);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isFav ? '已添加到收藏' : '已取消收藏'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              );
            case 'reader':
              return MangaReader(
                images: _store.currentChapterImages.toList(),
                isLoading: _store.isLoadingChapter,
                onBack: _store.backToDetail,
                onPageChanged: (page) {
                  // TODO: 更新阅读进度
                },
                ruleKey: _store.selectedRuleKey,
                chapterId: _store.currentChapterId,
                hasAccount: _store.supportsAccountForRule(_store.selectedRuleKey),
                onLogin: (username, password) {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value(false);
                  return _store.login(key, username, password);
                },
                onReLogin: () {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value(false);
                  return _store.reLogin(key);
                },
                onLogout: () {
                  final key = _store.selectedRuleKey;
                  if (key == null) return Future.value();
                  return _store.logout(key);
                },
                headers: _store.getReaderHeadersForRule(_store.selectedRuleKey),
                referer: _store.currentDetail != null
                    ? _store.getReaderRefererForRule(_store.selectedRuleKey)
                    : null,
                cdnFallbacks: _store.getCdnFallbacksForCurrentRule(),
                forceWebView: _store.getUseWebviewForRule(_store.selectedRuleKey),
              );
            default:
              return _buildSearchView();
          }
        },
      ),
    );
  }

  Widget _buildSearchView() {
    // 将搜索回调提取到外面，避免Observer重建时丢失
    void handleSearch(String keyword) {
      print('[漫画页面] 收到搜索请求: $keyword');
      print('[漫画页面] Store实例: $_store');
      print('[漫画页面] Store类型: ${_store.runtimeType}');
      try {
        _store.search(keyword);
        print('[漫画页面] search方法调用完成');
      } catch (e) {
        print('[漫画页面] search方法调用异常: $e');
      }
    }
    
    return Column(
      children: [
        // 搜索栏 - 传递当前选择的规则名称
        Observer(
          builder: (context) {
            String? currentRuleName;
            if (_store.selectedRuleKey != null) {
              final rule = _store.availableRules
                  .where((rule) => rule.key == _store.selectedRuleKey)
                  .firstOrNull;
              currentRuleName = rule?.name;
              print('[漫画页面] 当前选择的规则: ${_store.selectedRuleKey} -> $currentRuleName');
            } else {
              print('[漫画页面] 未选择规则');
            }
            
            return MangaSearchBar(
              currentRuleName: currentRuleName,
              onSearch: handleSearch,
              isSearching: _store.isSearching,
              hasAccount: _store.selectedRuleHasAccount,
              onLogin: (username, password) {
                final key = _store.selectedRuleKey;
                if (key == null) return Future.value(false);
                return _store.login(key, username, password);
              },
              onReLogin: () {
                final key = _store.selectedRuleKey;
                if (key == null) return Future.value(false);
                return _store.reLogin(key);
              },
              onLogout: () {
                final key = _store.selectedRuleKey;
                if (key == null) return Future.value();
                return _store.logout(key);
              },
            );
          },
        ),
        
        // 搜索结果
        Expanded(
          child: MangaSearchResults(
            store: _store,
          ),
        ),
      ],
    );
  }
}