import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/widgets/bubble_action_menu.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';

/// v1.3.3 回归：长按选取文本、追问引用、气泡不透明度与磨砂。
///
/// 说明：气泡的「复制 / 选取文本 / 追问」通过 SelectionArea 的自定义上下文
/// 菜单提供（长按选中文字后由系统工具栏承载）。这类工具栏由 Flutter 自己
/// 渲染，widget 测试里不稳定，所以这里守住的是**机制存在**与**回调链路**，
/// 不逐个点菜单项。
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('气泡可选取文本（长按选中机制）', () {
    testWidgets('助手气泡外层有 SelectionArea，长按才能选中文字', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: ChatMessage.assistant('一段回答内容'))),
      );

      expect(
        find.byType(SelectionArea),
        findsOneWidget,
        reason: '没有 SelectionArea 就没法长按选取文本',
      );
      expect(find.text('一段回答内容'), findsOneWidget);
    });

    testWidgets('用户消息同样支持选取', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: ChatMessage.user('我的问题'))),
      );

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('我的问题'), findsOneWidget);
    });

    testWidgets('正文不再嵌套 SelectableText（否则会冒出两套菜单）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(MessageBubble(message: ChatMessage.assistant('回答'))),
      );

      expect(
        find.byType(SelectableText),
        findsNothing,
        reason: 'SelectableText 自带选区，会和外层 SelectionArea 冲突',
      );
    });

    testWidgets('传入 onFollowUp 时气泡持有该回调（追问入口的前提）',
        (WidgetTester tester) async {
      String? quoted;
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage.assistant('回答'),
            onFollowUp: (String t) => quoted = t,
          ),
        ),
      );

      final MessageBubble bubble = tester.widget<MessageBubble>(
        find.byType(MessageBubble),
      );
      expect(bubble.onFollowUp, isNotNull);
      // 直接触发回调，验证聊天页这一端的链路可用
      bubble.onFollowUp!('选中的文字');
      expect(quoted, '选中的文字');
    });
  });

  group('长按菜单形状（单个胶囊 / 多个圆角）', () {
    testWidgets('只有 1 项时用胶囊形', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => showBubbleMenu(
                context,
                anchor: const Rect.fromLTWH(40, 300, 200, 60),
                actions: const <BubbleMenuAction>[
                  BubbleMenuAction(label: '复制', icon: Icons.copy),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final ClipRRect clip = tester.widget<ClipRRect>(
        find.byType(ClipRRect).last,
      );
      final BorderRadius radius = clip.borderRadius as BorderRadius;
      expect(radius.topLeft.x, greaterThan(20), reason: '单项应为胶囊形');
    });

    testWidgets('有 2 项时用圆角矩形，且两项都可见', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => showBubbleMenu(
                context,
                anchor: const Rect.fromLTWH(40, 300, 200, 60),
                actions: const <BubbleMenuAction>[
                  BubbleMenuAction(label: '复制', icon: Icons.copy),
                  BubbleMenuAction(label: '选取文本', icon: Icons.text_fields),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final ClipRRect clip = tester.widget<ClipRRect>(
        find.byType(ClipRRect).last,
      );
      final BorderRadius radius = clip.borderRadius as BorderRadius;
      expect(radius.topLeft.x, lessThan(20), reason: '多项应为圆角矩形');
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('选取文本'), findsOneWidget);
    });
  });

  group('追问引用接入输入栏', () {
    testWidgets('有引用文字时输入栏显示引用条，点 ✕ 可清除', (WidgetTester tester) async {
      String? cleared;
      await tester.pumpWidget(
        wrap(
          ChatInputBar(
            onSend: (String _) async => true,
            onStop: () {},
            onPickImages: () {},
            onPickFiles: () {},
            onRemoveAttachment: (_) {},
            isLoading: false,
            enabled: true,
            quotedText: '被引用的原文',
            onClearQuote: () => cleared = 'yes',
          ),
        ),
      );

      expect(find.textContaining('被引用的原文'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(cleared, 'yes', reason: '点 ✕ 必须能清除引用');
    });

    testWidgets('没有引用时不显示引用条', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          ChatInputBar(
            onSend: (String _) async => true,
            onStop: () {},
            onPickImages: () {},
            onPickFiles: () {},
            onRemoveAttachment: (_) {},
            isLoading: false,
            enabled: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.format_quote), findsNothing);
    });

    testWidgets('只有引用、没有输入文字时发送按钮也是可用的', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          ChatInputBar(
            onSend: (String _) async => true,
            onStop: () {},
            onPickImages: () {},
            onPickFiles: () {},
            onRemoveAttachment: (_) {},
            isLoading: false,
            enabled: true,
            quotedText: '引用内容',
            onClearQuote: () {},
          ),
        ),
      );

      final IconButton send = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byIcon(Icons.arrow_upward_rounded),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(
        send.onPressed,
        isNotNull,
        reason: '引用后即使没输入文字，也应该能发送（追问场景）',
      );
    });
  });

  group('气泡不透明度', () {
    test('默认 0.8，范围常量合法', () {
      expect(AppSettings.defaultBubbleOpacity, 0.8);
      expect(
        AppSettings.minBubbleOpacity,
        lessThan(AppSettings.defaultBubbleOpacity),
      );
      expect(
        AppSettings.maxBubbleOpacity,
        greaterThan(AppSettings.defaultBubbleOpacity),
      );
    });

    test('JSON 往返保留不透明度', () {
      final AppSettings s = AppSettings(bubbleOpacity: 0.55);
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.bubbleOpacity, closeTo(0.55, 0.001));
    });

    test('旧数据缺字段时回落到默认值', () {
      final AppSettings back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.bubbleOpacity, AppSettings.defaultBubbleOpacity);
    });

    test('越界值被夹到合法范围（防止旧数据把气泡弄成全透明）', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{'bubbleOpacity': 0.0})
            .bubbleOpacity,
        AppSettings.minBubbleOpacity,
      );
      expect(
        AppSettings.fromJson(<String, dynamic>{'bubbleOpacity': 5.0})
            .bubbleOpacity,
        AppSettings.maxBubbleOpacity,
      );
    });

    test('copyWith 能单独改不透明度，不影响其他字段', () {
      final AppSettings s = AppSettings(apiKey: 'sk-x', bubbleOpacity: 0.9);
      final AppSettings t = s.copyWith(bubbleOpacity: 0.5);
      expect(t.bubbleOpacity, closeTo(0.5, 0.001));
      expect(t.apiKey, 'sk-x');
    });
  });

  group('磨砂开关与性能保护', () {
    testWidgets('没开磨砂时不使用 BackdropFilter（避免白付 GPU 开销）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage.assistant('回答'),
            frosted: false,
          ),
        ),
      );

      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: '没有自定义背景时不应该加模糊层',
      );
    });

    testWidgets('开了磨砂时使用 BackdropFilter', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          MessageBubble(
            message: ChatMessage.assistant('回答'),
            frosted: true,
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('消息列表把新参数传给气泡', () {
    testWidgets('不透明度与磨砂开关会传到每条气泡', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          MessageListView(
            messages: <ChatMessage>[
              ChatMessage.user('hi'),
              ChatMessage.assistant('hello'),
            ],
            isLoading: false,
            bubbleOpacity: 0.6,
            frosted: true,
          ),
        ),
      );

      final Iterable<MessageBubble> bubbles = tester.widgetList<MessageBubble>(
        find.byType(MessageBubble),
      );
      expect(bubbles, isNotEmpty);
      for (final MessageBubble b in bubbles) {
        expect(b.bubbleOpacity, closeTo(0.6, 0.001));
        expect(b.frosted, isTrue);
      }
    });

    testWidgets('默认不透明度是 0.8，且默认不开磨砂', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          MessageListView(
            messages: <ChatMessage>[ChatMessage.assistant('hello')],
            isLoading: false,
          ),
        ),
      );

      final MessageBubble b = tester.widget<MessageBubble>(
        find.byType(MessageBubble),
      );
      expect(b.bubbleOpacity, AppSettings.defaultBubbleOpacity);
      expect(b.frosted, isFalse);
    });
  });
}
