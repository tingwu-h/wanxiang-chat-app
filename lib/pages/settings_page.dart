import 'package:deepseek_chat/models/model_info.dart';
import 'package:deepseek_chat/models/provider_catalog.dart';
import 'package:deepseek_chat/services/api_protocol.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/pages/about_page.dart';
import 'package:deepseek_chat/pages/model_behaviour_page.dart';
import 'package:deepseek_chat/pages/search_settings_page.dart';
import 'package:deepseek_chat/utils/app_info.dart';
import 'package:deepseek_chat/widgets/model_tags.dart';
import 'package:deepseek_chat/widgets/appearance_settings.dart';
import 'package:deepseek_chat/widgets/provider_tags.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/utils/link_actions.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';

/// 分组设置；编辑草稿在折叠和切换分类时保留，保存后才落盘。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.serviceFactory});

  final DeepSeekService Function()? serviceFactory;

  static const String routeName = '/settings';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _keyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _promptController;
  late final TextEditingController _customController;

  late AppSettings _draft;
  late String _model;
  bool? _imageSupport;
  late String _themeMode;
  late double _temperature;

  /// 下拉框里「自定义…」那一项的占位值（不是真实模型名）
  static const String _customModelSentinel = '__custom__';

  /// 当前模型是否不在预置列表里
  bool _isCustomModel = false;

  bool _obscureKey = true;
  bool _testing = false;
  bool _exporting = false;
  bool _saving = false;
  bool _resetting = false;
  bool _clearing = false;
  bool _themeSaving = false;
  bool _dirty = false;
  bool _loading = false;
  bool _allowPop = false;
  bool _leaving = false;
  String? _modelError;
  String? _keyError;
  String? _urlError;
  String? _connectionStatus;
  final Set<String> _expanded = {};
  bool get _busy =>
      _saving || _testing || _resetting || _clearing || _themeSaving;

  void _changed() {
    if (_loading || !mounted) return;
    setState(() {
      _dirty = true;
      _connectionStatus = null;
      _modelError = null;
      _keyError = null;
      _urlError = null;
    });
  }

  bool _validate({bool requireKey = false}) {
    final next = _collect();
    String? urlError;
    try {
      ApiProtocol.endpoint(next);
    } catch (_) {
      urlError = tr(context, '请填写有效的接口地址');
    }
    setState(() {
      _modelError = next.model.isEmpty ? tr(context, '请选择或填写模型') : null;
      _keyError = requireKey && !next.hasApiKey
          ? tr(context, '请先填写 API Key')
          : null;
      _urlError = urlError;
      if (_modelError != null || _keyError != null || _urlError != null) {
        _expanded.add('model');
        if (_urlError != null) _expanded.add('advanced');
      }
    });
    if (_modelError != null || _keyError != null || _urlError != null) {
      _toast(tr(context, '请检查「模型与服务」中的提示'), isError: true);
      return false;
    }
    return true;
  }

  Future<void> _leave() async {
    if (_busy || _leaving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    _leaving = true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, '保存修改？')),
        content: Text(tr(context, '还有未保存的设置。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(tr(context, '继续编辑')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(tr(context, '放弃修改')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(tr(context, '保存并返回')),
          ),
        ],
      ),
    );
    _leaving = false;
    if (!mounted || action == null || action == 'cancel') return;
    if (action == 'save' && !await _save()) return;
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<bool> _confirmDestination(AppSettings next) async {
    Uri destination;
    try {
      destination = ApiProtocol.endpoint(next);
    } on DeepSeekException catch (e) {
      _toast(e.message, isError: true);
      return false;
    } catch (_) {
      _toast(tr(context, '接口地址格式不正确，请检查后再试。'), isError: true);
      return false;
    }
    final previous = context.read<AppSettingsProvider>().settings;
    Uri? old;
    try {
      old = ApiProtocol.endpoint(previous);
    } catch (_) {}
    if (destination.origin != old?.origin && next.hasApiKey) {
      return await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(context, '确认接口接收方')),
              content: Text(
                localized(
                  context,
                  '密钥和聊天内容将发送到 ${destination.origin}。\n\n如果这是其他服务商，请确认填写的是该服务商的密钥。',
                  '金鑰與聊天內容將傳送至 ${destination.origin}。\n\n請確認金鑰屬於此服務商。',
                  'Your key and chat content will be sent to ${destination.origin}.\n\nMake sure the key belongs to this provider.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr(context, '返回检查')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(context, '确认使用')),
                ),
              ],
            ),
          ) ??
          false;
    }
    return true;
  }

  Future<void> _exportHistory() async {
    setState(() => _exporting = true);
    try {
      final json = await context.read<ChatProvider>().exportHistory();
      final saved = await PlatformService.exportHistory(json);
      if (mounted) {
        _toast(
          saved ? tr(context, '聊天文字已导出，图片文件不包含在内。') : tr(context, '已取消导出'),
        );
      }
    } catch (_) {
      if (mounted) _toast(tr(context, '导出失败，请重新选择保存位置。'), isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final AppSettings s = context.read<AppSettingsProvider>().settings;
    _draft = s;
    _imageSupport = s.imageSupport;
    _keyController = TextEditingController(text: s.apiKey);
    _baseUrlController = TextEditingController(text: s.baseUrl);
    _promptController = TextEditingController(text: s.systemPrompt);
    _model = s.model;
    _isCustomModel = !_draft.preset.models.contains(_model);
    _customController = TextEditingController(
      text: _isCustomModel ? _model : '',
    );
    _themeMode = s.themeMode;
    _temperature = s.temperature;
    for (final c in [
      _keyController,
      _baseUrlController,
      _promptController,
      _customController,
    ]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _promptController.dispose();
    _customController.dispose();
    super.dispose();
  }

  void _switchProvider(String id) {
    final next = _collect().forProvider(id);
    _loading = true;
    setState(() {
      _draft = next;
      _imageSupport = next.imageSupport;
      _keyController.text = next.apiKey;
      _baseUrlController.text = next.baseUrl;
      _model = next.model;
      _temperature = next.temperature;
      _isCustomModel = !next.preset.models.contains(_model);
      _customController.text = _isCustomModel ? _model : '';
      _obscureKey = true;
    });
    _loading = false;
    _changed();
  }

  AppSettings _collect() {
    // 自定义模型名优先：用户既然填了，就用他填的
    final String custom = _customController.text.trim();
    final String model = _isCustomModel ? custom : _model;
    return _draft.copyWith(
      imageSupport: _imageSupport,
      apiKey: _keyController.text.trim(),
      baseUrl: _baseUrlController.text.trim().isEmpty
          ? _draft.preset.url
          : _baseUrlController.text.trim(),
      model: model,
      systemPrompt: _promptController.text.trim(),
      temperature: _temperature,
      themeMode: _themeMode,
    );
  }

  Future<bool> _save() async {
    if (_busy || !_validate()) return false;
    setState(() => _saving = true);
    try {
      final next = _collect();
      if (!await _confirmDestination(next) || !mounted) return false;
      await context.read<AppSettingsProvider>().replace(next);
      if (!mounted) return false;
      setState(() {
        _draft = next;
        _dirty = false;
      });
      _toast(tr(context, '设置已保存'));
      return true;
    } catch (_) {
      if (mounted) _toast(tr(context, '保存失败，请重试'), isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_busy || !_validate(requireKey: true)) return;
    final candidate = _collect();
    setState(() {
      _testing = true;
      _connectionStatus = tr(context, '正在测试…');
    });
    final service = widget.serviceFactory?.call() ?? DeepSeekService();
    try {
      if (!await _confirmDestination(candidate) || !mounted) {
        if (mounted) setState(() => _connectionStatus = null);
        return;
      }
      FocusScope.of(context).unfocus();
      final reply = await service.testConnection(candidate);
      if (mounted) {
        setState(
          () => _connectionStatus = tr(context, '连接成功：{reply}', {
            'reply': _short(reply),
          }),
        );
      }
    } on DeepSeekException catch (e) {
      if (mounted) setState(() => _connectionStatus = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _connectionStatus = tr(context, '连接失败，请检查网络和配置'));
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _setTheme(String value) async {
    if (_busy) return;
    setState(() => _themeSaving = true);
    try {
      await context.read<AppSettingsProvider>().update(themeMode: value);
      if (mounted) setState(() => _themeMode = value);
    } catch (_) {
      if (mounted) _toast(tr(context, '主题未能保存，请重试'), isError: true);
    } finally {
      if (mounted) setState(() => _themeSaving = false);
    }
  }

  String _short(String text) {
    final String oneLine = text.replaceAll('\n', ' ').trim();
    if (oneLine.isEmpty) return tr(context, '（空回复）');
    return oneLine.length <= 30 ? oneLine : '${oneLine.substring(0, 30)}…';
  }

  /// 打开 DeepSeek 开放平台（申请 API Key）——逻辑统一在 link_actions.dart
  Future<void> _openPlatform() async {
    if (_draft.preset.platform.isNotEmpty) {
      await openExternalUrl(context, _draft.preset.platform);
    }
  }

  void _toast(String message, {bool isError = false}) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: isError ? 4 : 2),
          content: Text(message),
          backgroundColor: isError ? scheme.errorContainer : null,
          showCloseIcon: isError,
        ),
      );
  }

  Future<void> _confirmReset() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(tr(context, '恢复默认设置？')),
        content: Text(tr(context, '将清空已保存的 API Key、系统提示词等全部配置。')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, '恢复')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted || _busy) return;
    setState(() => _resetting = true);
    try {
      final provider = context.read<AppSettingsProvider>();
      await provider.resetToDefaults();
      if (!mounted) return;
      _loading = true;
      setState(() {
        _draft = provider.settings;
        _imageSupport = null;
        _customController.clear();
        _isCustomModel = false;
        _keyController.clear();
        _baseUrlController.text = AppSettings.defaultBaseUrl;
        _promptController.clear();
        _model = AppSettings.defaultModel;
        _themeMode = 'system';
        _temperature = 1.0;
        _dirty = false;
        _modelError = _urlError = _keyError = _connectionStatus = null;
      });
      _toast(tr(context, '已恢复默认设置'));
    } catch (_) {
      if (mounted) _toast(tr(context, '恢复失败，请重试'), isError: true);
    } finally {
      _loading = false;
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, '清空全部对话？')),
        content: Text(tr(context, '聊天记录和不再使用的图片将被删除，无法撤销。建议先导出重要内容。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(context, '确认清空')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await context.read<ChatProvider>().clearAllConversations();
      if (mounted) _toast(tr(context, '已清空全部对话'));
    } catch (_) {
      if (mounted) _toast(tr(context, '清理失败，请重试'), isError: true);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final currentModel = _collect().model;
    return PopScope(
      canPop: _allowPop || (!_dirty && !_busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(context, '设置')),
          leading: BackButton(onPressed: _busy ? null : _leave),
          actions: [
            IconButton(
              tooltip: tr(context, '设置帮助'),
              onPressed: () => _help(
                tr(context, '设置帮助'),
                tr(
                  context,
                  '展开分类进行修改，完成后点击保存。主题选择后立即生效。测试连接会产生真实 API 用量，但不会自动保存配置。',
                ),
              ),
              icon: const Icon(Icons.help_outline),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _saving
                        ? tr(context, '正在保存…')
                        : _dirty
                        ? tr(context, '有未保存的修改')
                        : '',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 48),
                  ),
                  onPressed: _busy || !_dirty ? null : () => _save(),
                  icon: const Icon(Icons.check),
                  label: Text(tr(context, '保存')),
                ),
              ],
            ),
          ),
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (settings.initializationWarning case final String warning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(warning),
                ),
              _group(
                'model',
                Icons.hub_outlined,
                tr(context, '模型与服务'),
                '${_draft.preset.name} · ${_keyController.text.trim().isEmpty ? '待配置' : '已填写密钥'}',
                [
                  DropdownButtonFormField<String>(
                    borderRadius: BorderRadius.circular(20),
                    key: ValueKey('provider-${_draft.providerId}'),
                    initialValue: _draft.providerId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr(context, '服务商')),
                    selectedItemBuilder: (_) => [
                      for (final p in providerCatalog)
                        Text(p.name, overflow: TextOverflow.ellipsis),
                    ],
                    items: [
                      for (final p in providerCatalog)
                        DropdownMenuItem(
                          value: p.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, overflow: TextOverflow.ellipsis),
                                Text(
                                  providerTags(p.id)
                                      .map((tag) => tr(context, tag))
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    itemHeight: null,
                    onChanged: (id) {
                      if (id != null) _switchProvider(id);
                    },
                  ),
                  const SizedBox(height: 12),
                  ProviderTags(providerId: _draft.providerId),
                  const SizedBox(height: 6),
                  Text(
                    localized(
                      context,
                      '服务商参考方向，具体能力以所选模型为准',
                      '服務商參考方向，具體能力以所選模型為準',
                      'Provider guidance; capabilities depend on the selected model',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _chooseFreeModel,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(tr(context, '选择免费模型')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: '${_draft.preset.name} API Key',
                      errorText: _keyError,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _obscureKey
                                ? tr(context, '显示')
                                : tr(context, '隐藏'),
                            onPressed: () =>
                                setState(() => _obscureKey = !_obscureKey),
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: tr(context, '粘贴'),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (!mounted || _busy) return;
                              if (data?.text case final String value) {
                                _keyController.text = value.trim();
                              }
                            },
                            icon: const Icon(Icons.content_paste),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_draft.preset.platform.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _openPlatform,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(tr(context, '获取 API Key')),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _help(
                        tr(context, '如何获取 API Key'),
                        _draft.preset.platform.isEmpty
                            ? tr(context, '向你的接口服务商申请密钥，复制后回到这里粘贴。')
                            : localized(
                                context,
                                '1. 点击「获取 API Key」，前往官方平台。\n2. 注册或登录，在 API Key 页面创建密钥。\n3. 复制密钥，返回万象粘贴并保存。\n\nChatGPT 等聊天会员不等于 API 额度。请在官方平台确认可用模型和费用。',
                                '1. 點擊「取得 API Key」前往官方平台。\n2. 註冊或登入並建立金鑰。\n3. 複製金鑰，返回萬象貼上並儲存。\n\n聊天會員不包含 API 額度，請向官方確認模型及費用。',
                                '1. Tap Get an API Key to open the official platform.\n2. Sign up or sign in and create a key.\n3. Copy the key, return to Wanxiang, paste and save.\n\nChat subscriptions do not include API credits. Check models and pricing with the provider.',
                              ),
                      ),
                      child: Text(tr(context, '申请步骤')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    borderRadius: BorderRadius.circular(20),
                    key: ValueKey(
                      'model-${_draft.providerId}-$_model-$_isCustomModel',
                    ),
                    initialValue: _isCustomModel
                        ? _customModelSentinel
                        : _model,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr(context, '模型')),
                    selectedItemBuilder: (context) => [
                      for (final m in _draft.modelChoices)
                        Text(m, overflow: TextOverflow.ellipsis),
                      Text(tr(context, '自定义模型')),
                    ],
                    items: [
                      for (final m in _draft.modelChoices)
                        DropdownMenuItem(
                          value: m,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(m, overflow: TextOverflow.ellipsis),
                              Text(
                                modelInfo(_draft.providerId, m).tags
                                    .map((tag) => tr(context, tag))
                                    .join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      DropdownMenuItem(
                        value: _customModelSentinel,
                        child: Text(tr(context, '自定义模型')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _isCustomModel = value == _customModelSentinel;
                        _model = _isCustomModel
                            ? _customController.text.trim()
                            : value;
                        _imageSupport = null;
                      });
                      _changed();
                    },
                  ),
                  if (_isCustomModel) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customController,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: tr(context, '模型 ID'),
                        hintText: tr(context, '填写服务商提供的模型 ID'),
                        errorText: _modelError,
                      ),
                    ),
                  ] else if (_modelError != null)
                    Text(_modelError!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                  ModelTags(providerId: _draft.providerId, model: currentModel),
                  if (modelFreeNote(_draft.providerId, currentModel)
                      case final String note)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tr(context, note),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (modelInfo(_draft.providerId, currentModel).detailsUrl
                      case final String url)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => openExternalUrl(context, url),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(tr(context, '查看免费额度说明')),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _group(
                    'advanced',
                    Icons.tune,
                    tr(context, '高级设置'),
                    tr(context, '接口地址与协议'),
                    [
                      TextField(
                        controller: _baseUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: tr(context, '接口地址'),
                          hintText: _draft.preset.url,
                          errorText: _urlError,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        borderRadius: BorderRadius.circular(20),
                        key: ValueKey(
                          'protocol-${_draft.providerId}-${_draft.protocol}',
                        ),
                        initialValue: _draft.protocol,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr(context, '接口协议'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'openai',
                            child: Text(tr(context, 'OpenAI 兼容')),
                          ),
                          const DropdownMenuItem(
                            value: 'responses',
                            child: Text('OpenAI Responses'),
                          ),
                          const DropdownMenuItem(
                            value: 'anthropic',
                            child: Text('Anthropic Messages'),
                          ),
                          const DropdownMenuItem(
                            value: 'gemini',
                            child: Text('Google Gemini'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(
                              () => _draft = _draft.copyWith(protocol: value),
                            );
                            _changed();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _testConnection,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(
                      _testing ? tr(context, '正在测试…') : tr(context, '测试连接'),
                    ),
                  ),
                  Text(
                    tr(context, '会产生 API 用量；测试不会自动保存。'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (_connectionStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_connectionStatus!),
                    ),
                ],
              ),
              _group(
                'chat',
                Icons.chat_bubble_outline,
                tr(context, '对话设置'),
                tr(context, '回复风格与图片'),
                [
                  TextField(
                    controller: _promptController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: tr(context, '系统提示词'),
                      hintText: tr(context, '例如：回答简洁，优先使用中文'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr(context, '回答发散度  {value}', {
                      'value': _temperature.toStringAsFixed(1),
                    }),
                  ),
                  // DeepSeek 思考模式下 temperature 不生效（官方明确），
                  // 这里置灰并说明，避免用户以为滑块坏了。
                  Builder(
                    builder: (BuildContext context) {
                      final bool disabled =
                          _draft.providerId == 'deepseek' &&
                          settings.settings.thinkingEnabled;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AbsorbPointer(
                            absorbing: disabled,
                            child: Opacity(
                              opacity: disabled ? 0.45 : 1,
                              child: Slider(
                                value: _temperature.clamp(0, 2),
                                min: 0,
                                max: 2,
                                divisions: 20,
                                label: _temperature.toStringAsFixed(1),
                                onChanged: (value) {
                                  setState(() => _temperature = value);
                                  _changed();
                                },
                              ),
                            ),
                          ),
                          if (disabled)
                            Text(
                              tr(context, '思考模式下温度设置不生效'),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr(context, '更稳定')),
                      Text(tr(context, '更多变化')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, '允许发送图片')),
                    subtitle: Text(
                      tr(context, '当前模型：{model}', {
                        'model': AppSettings.modelShortName(currentModel),
                      }),
                    ),
                    value: _imageSupport ?? modelSupportsImages(currentModel),
                    onChanged: (value) {
                      setState(() => _imageSupport = value);
                      _changed();
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _help(
                        tr(context, '图片能力'),
                        tr(context, '仅对支持图片的模型开启。自定义模型的能力以服务商说明为准。'),
                      ),
                      child: Text(tr(context, '如何选择？')),
                    ),
                  ),
                ],
              ),
              _group(
                'appearance',
                Icons.palette_outlined,
                tr(context, '外观设置'),
                _themeLabel(_themeMode),
                [
                  for (final mode in AppSettings.availableThemeModes)
                    RadioListTile<String>(
                      value: mode,
                      // ignore: deprecated_member_use
                      groupValue: _themeMode,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        if (value != null) _setTheme(value);
                      },
                      contentPadding: EdgeInsets.zero,
                      title: Text(_themeLabel(mode)),
                    ),
                  Text(
                    tr(context, '主题立即生效'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  AppearanceSettings(
                    onSaved: (settings) {
                      if (!mounted) return;
                      setState(
                        () => _draft = _draft.copyWith(
                          language: settings.language,
                          chatBackgroundColor: settings.chatBackgroundColor,
                          chatBackgroundImage: settings.chatBackgroundImage,
                        ),
                      );
                    },
                  ),
                ],
              ),
              _group(
                'search',
                Icons.travel_explore,
                tr(context, '联网与模型行为'),
                tr(context, '联网检索、模型行为与图片档位'),
                [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.psychology_outlined),
                    title: Text(tr(context, '模型行为')),
                    subtitle: Text(
                      tr(context, '深度思考、推理强度、图片档位与时间注入'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(ModelBehaviourPage.routeName),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune),
                    title: Text(tr(context, '联网搜索设置')),
                    subtitle: Text(
                      settings.settings.searchEnabled
                          ? tr(context, '联网搜索：已开启（点击关闭）')
                          : tr(context, '联网搜索：已关闭（点击开启）'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(SearchSettingsPage.routeName),
                  ),
                ],
              ),
              _group(
                'data',
                Icons.folder_outlined,
                tr(context, '数据管理'),
                tr(context, '导出、清理与重置'),
                [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text(
                      _exporting ? tr(context, '正在导出…') : tr(context, '导出聊天文字'),
                    ),
                    subtitle: Text(tr(context, '不含密钥和图片文件')),
                    onTap: _exporting ? null : _exportHistory,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(tr(context, '清空全部对话')),
                    onTap: _clearHistory,
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restart_alt),
                    title: Text(tr(context, '恢复默认设置')),
                    subtitle: Text(tr(context, '清除配置，保留聊天记录')),
                    onTap: _confirmReset,
                  ),
                ],
              ),
              _group(
                'about',
                Icons.info_outline,
                tr(context, '关于万象'),
                'v$kAppVersion',
                [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/branding/icon.png',
                        width: 44,
                        height: 44,
                      ),
                    ),
                    title: Text(tr(context, '万象')),
                    subtitle: Text(
                      tr(context, '版本 v{version}', {'version': kAppVersion}),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).pushNamed(AboutPage.routeName),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, '项目主页')),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => openExternalUrl(context, kProjectRepoUrl),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, '使用许可')),
                    subtitle: Text(tr(context, '源码公开，禁止商用')),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => openExternalUrl(
                      context,
                      '$kProjectRepoUrl/blob/main/LICENSE',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseFreeModel() async {
    final choices = [
      ('openrouter', 'openrouter/free', tr(context, '免费模型自动选择')),
      (
        'openrouter',
        'qwen/qwen3.8-27b:free',
        tr(context, 'Qwen 3.8 27B · 免费变体'),
      ),
      (
        'google',
        'gemini-2.5-flash-lite',
        tr(context, 'Gemini Flash-Lite · 免费额度'),
      ),
    ];
    final choice = await showModalBottomSheet<(String, String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr(context, '选择免费模型')),
                subtitle: Text(tr(context, '需自己的 API Key，额度以官方平台为准')),
              ),
              for (final item in choices)
                ListTile(
                  title: Text(item.$3),
                  subtitle: Text(presetFor(item.$1).name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, item),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    _switchProvider(choice.$1);
    setState(() {
      _model = choice.$2;
      _isCustomModel = false;
      _imageSupport = null;
      _expanded.add('model');
    });
    _changed();
  }

  String _themeLabel(String mode) => switch (mode) {
    'light' => tr(context, '浅色'),
    'dark' => tr(context, '深色'),
    _ => tr(context, '跟随系统'),
  };

  Future<void> _help(String title, String text) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(context, '知道了')),
        ),
      ],
    ),
  );

  Widget _group(
    String id,
    IconData icon,
    String title,
    String summary,
    List<Widget> children,
  ) {
    final open = _expanded.contains(id);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: open,
            child: Material(
              key: ValueKey('section-header-$id'),
              type: MaterialType.transparency,
              clipBehavior: Clip.hardEdge,
              child: ListTile(
                key: ValueKey('section-$id'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: Icon(icon, color: scheme.primary),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    if (open) {
                      _expanded.remove(id);
                    } else {
                      _expanded.add(id);
                    }
                  });
                },
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
