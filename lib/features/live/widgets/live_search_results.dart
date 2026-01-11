/// Live search results widget
library;

import 'package:flutter/material.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'live_room_card.dart';

class LiveSearchResults extends StatelessWidget {
  final List<LiveRoomItem> results;
  final bool isLoading;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final Function(LiveRoomItem) onRoomTap;
  final String emptyMessage;

  const LiveSearchResults({
    super.key,
    required this.results,
    this.isLoading = false,
    this.hasMore = false,
    this.onLoadMore,
    required this.onRoomTap,
    this.emptyMessage = '暂无结果',
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          // 加载更多按钮
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: onLoadMore,
                      child: const Text('加载更多'),
                    ),
            ),
          );
        }

        final room = results[index];
        return LiveRoomCard(
          room: room,
          onTap: () => onRoomTap(room),
        );
      },
    );
  }
}