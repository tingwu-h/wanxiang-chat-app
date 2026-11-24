import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:flutter/material.dart';

import 'package:deepseek_chat/utils/app_info.dart';
import 'package:deepseek_chat/utils/link_actions.dart';
import 'package:deepseek_chat/services/update_service.dart';

/// 关于页：版本号、创作者、相关链接。
///
/// 版本号从设置页底部挪到了这里（设置页底部不再显示）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String routeName = '/about';

  static const String _repoUrl = kProjectRepoUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '关于'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: <Widget>[
          // 应用标识 + 版本号
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/branding/icon.png'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(context, '万象'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, '版本 v{version}', {'version': kAppVersion}),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // 创作者：点了跳到 GitHub 主页
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(tr(context, '创作者')),
              subtitle: const Text(kAppAuthor),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openGithubProfile(context),
            ),
          ),

          const SizedBox(height: 12),

          const Card(child: _UpdateTile()),

          const SizedBox(height: 12),

          // 链接
          Card(
            child: Column(
              children: <Widget>[
                _LinkTile(
                  icon: Icons.code,
                  title: tr(context, '项目源码'),
                  subtitle: tr(context, '源码公开，禁止商用'),
                  url: _repoUrl,
                ),
                _LinkTile(
                  icon: Icons.description_outlined,
                  title: tr(context, '使用许可'),
                  subtitle: tr(context, '万象非商业使用许可证'),
                  url: '$_repoUrl/blob/main/LICENSE',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 免责说明
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              localized(
                context,
                '本应用是个人作品，与各模型服务商无隶属关系。\nAPI Key 在本机加密保存；请求时，密钥和聊天内容发送到你为当前服务商设置的接口。',
                '本應用為個人作品，與模型服務商無隸屬關係。\nAPI Key 在本機加密儲存；請求時金鑰與聊天內容會傳送至你設定的介面。',
                'An independent app, unaffiliated with model providers.\nAPI keys are encrypted on this device. Requests send your key and chat content to the endpoint you configure.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行可点击的链接：点了用系统浏览器打开
class _UpdateTile extends StatefulWidget {
  const _UpdateTile();

  @override
  State<_UpdateTile> createState() => _UpdateTileState();
}

class _UpdateTileState extends State<_UpdateTile> {
  final UpdateService _service = UpdateService();
  bool _checking = false;
  String? _result;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _result = null;
    });
    try {
      final UpdateInfo info = await _service.latest();
      if (!mounted) return;
      if (UpdateService.compareVersions(info.version, kAppVersion) > 0) {
        setState(() => _result = tr(context, '发现新版本 v{version}', {
          'version': info.version,
        }));
        await _showUpdate(info);
      } else {
        setState(() => _result = tr(context, '已是最新版本'));
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      setState(() => _result = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdate(UpdateInfo info) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(tr(ctx, '发现新版本 v{version}', {'version': info.version})),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              info.body.isEmpty ? tr(ctx, '暂无更新说明') : info.body,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, '稍后')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openExternalUrl(ctx, info.url);
            },
            child: Text(tr(ctx, '打开下载页')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: _checking
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: Text(tr(context, '检测更新')),
      subtitle: Text(
        _result ?? tr(context, '当前 v{version}', {'version': kAppVersion}),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _checking ? null : _check,
    );
  }
}

/// 一行可点击的链接：点了用系统浏览器打开
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 18),
      // 逻辑统一在 link_actions.dart（失败时会把网址显示出来）
      onTap: () => openExternalUrl(context, url),
    );
  }
}
