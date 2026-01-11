/// Live platform selector widget
library;

import 'package:flutter/material.dart';
import '../../../core/services/live_manager.dart';

class LivePlatformSelector extends StatelessWidget {
  final String currentPlatformId;
  final Function(String) onPlatformChanged;

  const LivePlatformSelector({
    super.key,
    required this.currentPlatformId,
    required this.onPlatformChanged,
  });

  @override
  Widget build(BuildContext context) {
    final allSites = LiveManager().allSites;
    
    if (allSites.length <= 1) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.swap_horiz),
      tooltip: '切换平台',
      onSelected: onPlatformChanged,
      itemBuilder: (context) {
        return allSites.map((site) {
          final isSelected = site.id == currentPlatformId;
          final isLoggedIn = LiveManager().isLoggedIn(site.id);
          final supportsLogin = LiveManager().supportsCookieLogin(site.id);
          
          return PopupMenuItem<String>(
            value: site.id,
            child: Row(
              children: [
                // 选中状态指示器
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 20,
                  color: isSelected 
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                
                const SizedBox(width: 12),
                
                // 平台名称
                Expanded(
                  child: Text(
                    site.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                
                // 登录状态指示器
                if (supportsLogin) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isLoggedIn ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
    );
  }
}