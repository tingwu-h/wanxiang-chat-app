import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/pages/plugin_settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/document_service.dart';
import 'package:deepseek_chat/services/platform_service.dart';
import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:deepseek_chat/utils/file_capability.dart';

/// 创建 Word / Excel / PPT：让模型产出 JSON，App 在本地组装文件。
class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key});

  static const String routeName = '/document';

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  DocType _type = DocType.word;
  final TextEditingController _topic = TextEditingController();
  bool _useConversation = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_busy) return;
    final AppSettingsProvider settings = context.read<AppSettingsProvider>();
    final ChatProvider chat = context.read<ChatProvider>();
    if (!supportsFileGeneration(settings.settings.providerId)) {
      setState(() => _error = tr(context, '当前服务商暂未适配文档生成，请切换到 DeepSeek'));
      return;
    }
    final String topic = _topic.text.trim();
    if (topic.isEmpty && !_useConversation) {
      setState(() => _error = tr(context, '请先填写主题，或勾选使用当前对话'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final DeepSeekService api = DeepSeekService();
    try {
      final String contextText = _useConversation
          ? _conversationText(chat)
          : '';
      final String raw = await api.completeChat(
        settings: settings.settings.copyWith(
          systemPrompt: DocumentService.systemPrompt(_type),
        ),
        history: <ChatMessage>[
          ChatMessage.user(
            DocumentService.userPrompt(
              _type,
              topic.isEmpty ? '根据当前对话内容整理' : topic,
              contextText,
            ),
          ),
        ],
      );
      final Uint8List bytes = await DocumentService.build(_type, raw);
      final String name = DocumentService.fileName(
        _type,
        topic.isEmpty ? '对话整理' : topic,
      );
      final bool saved = await PlatformService.saveFile(
        name,
        DocumentService.mimeTypes[_type]!,
        bytes,
      );
      if (!mounted) return;
      setState(() {
        _error = saved ? null : tr(context, '已取消保存');
      });
      if (saved) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(tr(context, '已保存：{name}', {'name': name}))),
          );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is DeepSeekException ? e.message : '生成失败：$e';
      });
    } finally {
      api.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  String _conversationText(ChatProvider chat) {
    final List<ChatMessage> messages = chat.messages;
    final StringBuffer sb = StringBuffer();
    for (final ChatMessage m in messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages) {
      if (m.content.trim().isEmpty) continue;
      sb.writeln('${m.isUser ? '用户' : '助手'}：${m.content.trim()}');
    }
    final String text = sb.toString().trim();
    return text.length > 6000 ? text.substring(text.length - 6000) : text;
  }

  @override
  Widget build(BuildContext context) {
    final AppSettingsProvider settings = context.watch<AppSettingsProvider>();
    final bool supported = supportsFileGeneration(
      settings.settings.providerId,
    );
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '创建文档'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          if (!supported)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tr(context, '文档生成目前仅适配 DeepSeek，请到设置里切换服务商。'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          SegmentedButton<DocType>(
            segments: <ButtonSegment<DocType>>[
              ButtonSegment<DocType>(
                value: DocType.word,
                label: Text(tr(context, 'Word')),
                icon: const Icon(Icons.description_outlined),
              ),
              ButtonSegment<DocType>(
                value: DocType.excel,
                label: Text(tr(context, 'Excel')),
                icon: const Icon(Icons.table_chart_outlined),
              ),
              ButtonSegment<DocType>(
                value: DocType.ppt,
                label: Text(tr(context, 'PPT')),
                icon: const Icon(Icons.slideshow_outlined),
              ),
            ],
            selected: <DocType>{_type},
            onSelectionChanged: (Set<DocType> value) {
              setState(() => _type = value.first);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _topic,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr(context, '主题或要点'),
              hintText: tr(context, '例如：2026 年第三季度工作总结，包含成绩、问题和下一步计划'),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, '使用当前对话内容')),
            subtitle: Text(tr(context, '把最近 12 条消息作为素材')),
            value: _useConversation,
            onChanged: (bool v) => setState(() => _useConversation = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy || !supported ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _busy ? tr(context, '正在生成…') : tr(context, '生成并保存'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            tr(
              context,
              '生成在本地完成，文件通过系统保存框写入；不会上传到第三方转换服务。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).pushNamed(PluginSettingsPage.routeName),
            icon: const Icon(Icons.psychology_alt_outlined),
            label: Text(tr(context, '打开指令插件')),
          ),
        ],
      ),
    );
  }
}
