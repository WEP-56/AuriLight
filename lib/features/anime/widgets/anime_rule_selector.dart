import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../anime_store.dart';

/// 动漫规则选择器
class AnimeRuleSelector extends StatelessWidget {
  final AnimeStore store;

  const AnimeRuleSelector({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final availableRules = store.availableRules;

        if (availableRules.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('没有可用的动漫规则'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('请在设置中添加动漫规则文件'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      // TODO: 导航到设置页面
                    },
                    child: const Text('添加规则'),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.source,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  '规则源:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField(
              initialValue: store.selectedRule,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              items: availableRules.map((rule) {
                return DropdownMenuItem(
                  value: rule,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: rule.enabled 
                              ? Colors.green 
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          rule.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'v${rule.version}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (rule) {
                if (rule != null) {
                  store.selectRule(rule);
                }
              },
            ),
          ],
        );
      },
    );
  }
}