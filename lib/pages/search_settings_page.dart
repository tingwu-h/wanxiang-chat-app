import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 联网搜索 + 模型行为设置。
///
/// 单独成页的原因：这些开关与「模型与服务」的草稿式保存无关，
/// 改一项就该立刻生效（用户需要马上看到联网按钮亮起来），
/// 所以这里全部走 AppSettingsProvider 即时落盘。
class SearchSettingsPage extends StatefulWidget {
  const SearchSettingsPage({super.key});

  static const String routeName = '/search-settings';

  @override
  State<SearchSettingsPage> createState() => _SearchSettingsPageState();
}

class _SearchSettingsPageState extends State<SearchSettingsPage> {
  final TextEditingController _keyController = TextEditingController();
  bool _keyInitialized = false;
  bool _busy = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _update(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr(context, '保存失败，请重试'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsProvider provider = context.watch<AppSettingsProvider>();
    final AppSettings s = provider.settings;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (!_keyInitialized) {
      _keyController.text = s.searchApiKey;
      _keyInitialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '联网搜索'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.travel_explore),
            title: Text(tr(context, '启用联网搜索')),
            subtitle: Text(
              s.canSearch
                  ? tr(context, '联网搜索：已开启（点击关闭）')
                  : tr(context, '联网搜索需要先填写 DeepSeek 的 API Key'),
            ),
            value: s.searchEnabled,
            onChanged: s.canSearch
                ? (bool v) => _update(
                    () => provider.updateSearch(enabled: v),
                  )
                : null,
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            tr(context, '搜索用 API Key'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: tr(context, '搜索用 API Key'),
              hintText: tr(context, '留空则复用 DeepSeek 服务商的 Key'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (String v) => _update(
              () => provider.updateSearch(apiKey: v.trim()),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => _update(
                () => provider.updateSearch(apiKey: _keyController.text.trim()),
              ),
              child: Text(tr(context, '保存')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, '结果条数：{count}', {'count': s.searchCount}),
            style: theme.textTheme.titleSmall,
          ),
          Slider(
            value: s.searchCount.toDouble().clamp(
              AppSettings.minSearchCount.toDouble(),
              AppSettings.maxSearchCount.toDouble(),
            ),
            min: AppSettings.minSearchCount.toDouble(),
            max: 20,
            divisions: 19,
            label: '${s.searchCount}',
            onChanged: (double v) => _update(
              () => provider.updateSearch(count: v.round()),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, '抓取正文')),
            subtitle: Text(
              tr(
                context,
                '抓取正文会让回答更准，但会额外产生搜索接口调用',
              ),
            ),
            value: s.searchFetch,
            onChanged: (bool v) => _update(
              () => provider.updateSearch(fetch: v),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, '显示来源链接')),
            value: s.showSources,
            onChanged: (bool v) => _update(
              () => provider.updateSearch(showSources: v),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tr(context, '联网搜索会收取费用：约每千次成功请求 0.75 美元'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    context,
                    '使用联网搜索时，你的问题会发送给 DeepSeek 搜索服务',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr(context, '思考模式、推理强度、图片档位与时间注入已移到「模型行为」页面'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
