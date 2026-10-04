import 'package:deepseek_chat/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';

/// 对话气泡列表。
///
/// 用 `reverse: true` + 倒序数据：新消息天然出现在底部，
/// 键盘弹出时也不用手动滚动到底。
class MessageListView extends StatefulWidget {
  const MessageListView({
    super.key,
    required this.messages,
    required this.isLoading,
  });

  final List<ChatMessage> messages;
  final bool isLoading;

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<MessageListView> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant MessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新消息进来时平滑滚到底部
    if (widget.messages.length != oldWidget.messages.length) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      // reverse 列表里 offset 0 就是「最新一条」
      _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage> messages = widget.messages;

    if (messages.isEmpty) {
      return const _EmptyHint();
    }

    // 最后一条助手消息正在流式接收时，需要显示输入光标/等待动画
    final int lastIndex = messages.length;
    final bool typingLast = widget.isLoading;

    return ListView.builder(
      controller: _controller,
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      // 数据倒序绑定，index 0 显示最新一条
      itemCount: lastIndex,
      itemBuilder: (BuildContext context, int index) {
        final int i = lastIndex - 1 - index;
        final ChatMessage message = messages[i];
        return MessageBubble(
          message: message,
          showTyping: typingLast && index == 0,
        );
      },
    );
  }
}

/// 空会话时的引导页。
///
/// 刻意保持极简：输入框已经写着「给万象发消息…」，
/// 屏幕中间只保留一句品牌文案。
/// 只有「还没配 API Key」这种用户必须知道的信息才显示。
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool hasApiKey = context.select<AppSettingsProvider, bool>(
      (AppSettingsProvider s) => s.hasApiKey,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              tr(context, '万象聚合，模型无界'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (!hasApiKey) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                tr(context, '还没配置 API Key，从左侧抽屉进入「设置」填写。'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              // 新用户第一眼就该有地方去申请，不用自己找网址
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(tr(context, '配置模型服务商')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
