import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../anime_store.dart';

/// 动漫搜索栏
class AnimeSearchBar extends StatefulWidget {
  final AnimeStore store;

  const AnimeSearchBar({
    super.key,
    required this.store,
  });

  @override
  State<AnimeSearchBar> createState() => _AnimeSearchBarState();
}

class _AnimeSearchBarState extends State<AnimeSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.store.searchKeyword;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _performSearch() {
    final keyword = _controller.text.trim();
    if (keyword.isNotEmpty) {
      widget.store.setSearchKeyword(keyword);
      widget.store.searchAnime();
    }
  }

  void _performTest() {
    final keyword = _controller.text.trim();
    if (keyword.isNotEmpty) {
      widget.store.setSearchKeyword(keyword);
      widget.store.testRuleSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '搜索动漫...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          widget.store.setSearchKeyword('');
                          widget.store.clearSearchResults();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              enabled: !widget.store.isLoading && widget.store.selectedRule != null,
              onChanged: (value) {
                setState(() {}); // 更新清除按钮的显示状态
              },
              onSubmitted: (_) => _performSearch(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    onPressed: widget.store.isLoading || 
                              widget.store.selectedRule == null || 
                              _controller.text.trim().isEmpty
                        ? null
                        : _performSearch,
                    child: widget.store.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('搜索'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: widget.store.isLoading || 
                              widget.store.selectedRule == null || 
                              _controller.text.trim().isEmpty
                        ? null
                        : _performTest,
                    child: const Text('测试'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}