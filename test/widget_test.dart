import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';
import 'package:deepseek_chat/widgets/message_list_view.dart';

/// 用假的 http.Client 替代真实网络请求。
class _FakeClient extends http.BaseClient {
  _FakeClient({this.streaming = true});

  final bool streaming;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String body = streaming
        // 一个思考帧 + 两个正文帧 + 结束标记
        // 思考帧用来验证 reasoning_content 不会被混进正文
        ? 'data: ${jsonEncode(<String, dynamic>{
                'choices': <dynamic>[
                  <String, dynamic>{
                    'delta': <String, dynamic>{'reasoning_content': '我需要先想想怎么回答。'},
                  },
                ],
              })}\n\n'
              'data: ${jsonEncode(<String, dynamic>{
                'choices': <dynamic>[
                  <String, dynamic>{
                    'delta': <String, dynamic>{'content': '你好'},
                  },
                ],
              })}\n\n'
              'data: ${jsonEncode(<String, dynamic>{
                'choices': <dynamic>[
                  <String, dynamic>{
                    'delta': <String, dynamic>{'content': '，世界'},
                  },
                ],
              })}\n\n'
              'data: [DONE]\n\n'
        : jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '你好，世界'},
              },
            ],
          });

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: <String, String>{'content-type': 'text/event-stream'},
    );
  }
}

Future<_Harness> _buildHarness({bool streaming = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final StorageService storage = StorageService();
  final AppSettingsProvider settings = AppSettingsProvider(storage: storage);
  await settings.init();
  await settings.update(apiKey: 'sk-test-key');

  final ChatProvider chat = ChatProvider(
    api: DeepSeekService(client: _FakeClient(streaming: streaming)),
    storage: storage,
  );
  await chat.init();
  addTearDown(chat.dispose);

  return _Harness(settings: settings, chat: chat);
}

class _Harness {
  _Harness({required this.settings, required this.chat});

  final AppSettingsProvider settings;
  final ChatProvider chat;

  Widget get app =>
      DeepSeekChatApp(settingsProvider: settings, chatProvider: chat);
}

void main() {
  testWidgets(
    'floating composer reserves space as typing grows; history scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final h = await _buildHarness();
      for (var i = 0; i < 12; i++) {
        await h.chat.send('历史消息 $i：保留这段内容，供上下滚动阅读。', h.settings.settings);
      }
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(MessageListView),
        matching: find.byType(ListView),
      );
      final controller = tester.widget<ListView>(list).controller!;
      final composer = find.byKey(const ValueKey('chat-bottom-surface'));
      final shortHeight = tester.getSize(composer).height;
      await tester.enterText(find.byType(TextField), '第一行\n第二行\n第三行\n第四行');
      await tester.pumpAndSettle();
      expect(tester.getSize(composer).height, greaterThan(shortHeight));
      final newest = find.byWidgetPredicate(
        (w) => w is MessageBubble && identical(w.message, h.chat.messages.last),
      );
      expect(
        tester.getBottomLeft(newest).dy,
        lessThan(tester.getTopLeft(composer).dy),
      );
      await tester.dragFrom(const Offset(195, 460), const Offset(0, 230));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      await tester.enterText(find.byType(TextField), '一行');
      await tester.pumpAndSettle();
      expect(tester.getSize(composer).height, shortHeight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('首页展示标题、输入框与发送按钮', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 顶部不再显示会话名称，空态只保留品牌文案。
    expect(find.byKey(const ValueKey('floating-top-bar')), findsOneWidget);
    expect(find.text('新对话'), findsNothing);
    expect(find.text('万象聚合，模型无界'), findsOneWidget);
    expect(find.text('给万象发消息…'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    // 空态不再重复教「怎么发消息」（输入框已有提示）
    expect(find.textContaining('一个字一个字'), findsNothing);
    expect(find.textContaining('在下面输入问题'), findsNothing);
  });

  testWidgets('⋮ 菜单包含新建与清空，停止生成保留在输入栏', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('新建对话'), findsOneWidget);
    expect(find.text('清空当前对话'), findsOneWidget);
    // 停止生成不该出现在菜单里——它已经集成在发送按钮上（生成时变 ⏹）
    expect(find.text('停止生成'), findsNothing);
    // 菜单里也不该有设置（设置在会话抽屉底部）
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('设置入口唯一：只在会话抽屉里（回归：曾齿轮/菜单/抽屉三处重复）', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 顶栏不再有齿轮图标
    expect(find.byIcon(Icons.settings_outlined), findsNothing);

    // ⋮ 菜单里有新建与清空，没有重复设置入口
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('清空当前对话'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    expect(find.text('API Key 与设置'), findsNothing);

    // 关掉菜单，打开会话抽屉，设置在这里
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('更多菜单可以新建对话，并保留原会话', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '第一轮提问');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && h.chat.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(h.chat.isLoading, isFalse);
    await tester.pumpAndSettle();
    expect(h.chat.messages.length, 2);
    final String? firstId = h.chat.activeConversationId;

    expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建对话'));
    await tester.pumpAndSettle();

    // 新会话应为空，且 id 变了
    expect(h.chat.messages, isEmpty);
    expect(h.chat.activeConversationId, isNot(firstId));
    // 旧会话仍在列表里
    expect(h.chat.conversations.length, greaterThanOrEqualTo(2));
  });

  testWidgets('输入框下方可以切换当前服务商的模型', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 默认 deepseek-flash，底部选择器显示 flash
    expect(find.text('DeepSeek · flash'), findsOneWidget);
    expect(h.settings.model, 'deepseek-flash');

    // 点开模型菜单，选 deepseek-v4-pro
    await tester.tap(find.text('DeepSeek · flash'));
    await tester.pumpAndSettle();
    expect(find.text('deepseek-v4-pro'), findsOneWidget);
    expect(find.text('OpenAI · GPT'), findsNothing);
    expect(find.text('Anthropic · Claude'), findsNothing);

    await tester.tap(find.text('deepseek-v4-pro'));
    await tester.pumpAndSettle();

    // 底部选择器更新，且已持久化到设置
    expect(find.text('DeepSeek · v4-pro'), findsOneWidget);
    expect(h.settings.model, 'deepseek-v4-pro');
  });

  testWidgets('发送消息后流式拼接助手回复', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // 助手回复由 flutter_markdown 渲染成富文本
    expect(find.textContaining('你好，世界'), findsOneWidget);
    expect(h.chat.messages.length, 2);

    // 回归：思考过程必须和正文分开，不能混在一起
    final ChatMessage reply = h.chat.messages.last;
    expect(reply.content, '你好，世界');
    expect(reply.content.contains('我需要先想想'), isFalse);
    expect(reply.thinking, '我需要先想想怎么回答。');
    // 思考过程默认收起，界面上只显示「点击展开」的提示
    expect(find.textContaining('思考过程'), findsOneWidget);
    expect(find.textContaining('我需要先想想'), findsNothing);
  });

  testWidgets('设置页显示 API Key 输入框（Key 不硬编码）', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 设置入口在会话抽屉底部
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('section-model')));
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek API Key'), findsOneWidget);
    // 之前保存的测试 Key 应该回填到输入框
    expect(find.text('sk-test-key'), findsOneWidget);

    // 「测试连接」按钮在页面底部，ListView 懒加载还没构建它，
    // 必须先滚动到底部再断言（这是测试写法，不是应用问题）。
    await tester.scrollUntilVisible(
      find.text('测试连接'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('测试连接'), findsOneWidget);
  });

  testWidgets('设置页改主题立即生效（回归：曾必须再点保存才生效）', (WidgetTester tester) async {
    final _Harness h = await _buildHarness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    // 初始跟随系统
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    // 进入设置页（入口在会话抽屉底部）
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('section-appearance')));
    await tester.pumpAndSettle();
    // 选择「深色」——不加任何保存操作。
    //
    // 这里刻意不用 find.ancestor(of: find.text('深色'), ...)：
    // 那个组合在「ListView 懒构建 + RadioListTile 内部结构」下会一个都找不到（已实测）。
    // 做法：先确认文本已构建 → 再分次拖拽把它挪进视口 → 点它。
    bool tapped = false;
    for (int i = 0; i < 14 && !tapped; i++) {
      final Finder darkText = find.text('深色');
      if (darkText.evaluate().isNotEmpty) {
        final Offset c = tester.getCenter(darkText);
        if (c.dy > 60 && c.dy < 550) {
          await tester.tap(darkText);
          tapped = true;
          break;
        }
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await tester.pumpAndSettle();
    }
    expect(tapped, isTrue, reason: '没能把「深色」选项滚进可点击区域');
    await tester.pumpAndSettle();

    // 立即生效：MaterialApp 变成 dark，且已持久化
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(h.settings.themeModeName, 'dark');
  });

  testWidgets(
    'single-row toolbar fits a small screen and keeps the model accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final h = await _buildHarness();
      await h.settings.selectProvider('anthropic');
      await h.settings.update(model: 'a-very-long-custom-model-name');
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      final topBar = find.byKey(const ValueKey('floating-top-bar'));
      expect(topBar, findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getSize(topBar).height, lessThanOrEqualTo(64));
      expect(find.byKey(const ValueKey('conversation-title')), findsNothing);
      expect(find.byIcon(Icons.add_comment_outlined), findsNothing);
      final selector = find.byKey(const ValueKey('chat-model-selector'));
      expect(
        tester.getTopLeft(selector).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(TextField)).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('message-composer')),
          matching: selector,
        ),
        findsOneWidget,
      );
      expect(
        tester.getBottomLeft(selector).dy,
        lessThan(
          tester
              .getBottomLeft(find.byKey(const ValueKey('message-composer')))
              .dy,
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).minLines, 1);
      expect(tester.getSize(selector).width, lessThanOrEqualTo(240));
      await tester.tap(find.byTooltip('切换模型'));
      await tester.pumpAndSettle();
      expect(find.text('a-very-long-custom-model-name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact model menu scrolls both ways and selects offscreen models',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      final h = await _buildHarness();
      for (var i = 0; i < 10; i++) {
        await h.settings.update(model: 'custom-model-$i');
      }
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换模型'));
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).last;
      final scrollable = find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      );
      expect(tester.getSize(scroll).height, lessThanOrEqualTo(240));
      expect(tester.getTopLeft(scroll).dy, greaterThan(400));
      final last = find.text('custom-model-9');
      expect(last.hitTestable(), findsOneWidget);
      final first = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'deepseek-flash',
      );
      await tester.scrollUntilVisible(first, -160, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(first.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(first).dy,
        inInclusiveRange(
          tester.getTopLeft(scroll).dy,
          tester.getTopLeft(scroll).dy + 8,
        ),
      );
      await tester.scrollUntilVisible(last, 160, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(h.settings.model, 'custom-model-9');
      await tester.tap(find.byTooltip('切换模型'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(first, -160, scrollable: scrollable);
      await tester.pumpAndSettle();
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(h.settings.model, 'deepseek-flash');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 24);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换模型'));
      await tester.pumpAndSettle();
      expect(tester.getSize(scroll).height, lessThan(200));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floating toolbar stays title-free when conversations are renamed',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 270);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final h = await _buildHarness();
      await h.chat.newConversation();
      final id = h.chat.activeConversationId!;
      await h.chat.renameConversation(id, '我的长会话名称测试：旅行计划与每日安排');
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('floating-top-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('conversation-title')), findsNothing);
      await h.chat.renameConversation(id, '新名称');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('floating-top-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('conversation-title')), findsNothing);
      expect(
        tester
            .getBottomLeft(find.byKey(const ValueKey('chat-model-selector')))
            .dy,
        lessThanOrEqualTo(370),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear current remains confirmed and preserves other conversations',
    (tester) async {
      final h = await _buildHarness();
      await tester.pumpWidget(h.app);
      await tester.enterText(find.byType(TextField), '保留这段对话');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      for (var i = 0; i < 100 && h.chat.isLoading; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(h.chat.messages.length, 2);
      expect(h.chat.isLoading, isFalse);
      final original = h.chat.activeConversationId;
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建对话'));
      await tester.pumpAndSettle();
      final target = h.chat.activeConversationId;
      expect(target, isNot(original));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空当前对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.chat.activeConversationId, target);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空当前对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(h.chat.conversations.any((c) => c.id == target), isFalse);
      expect(
        h.chat.conversations.any(
          (c) => c.id == original && c.messages.isNotEmpty,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('AppSettings 默认值正确', () {
    final AppSettings s = AppSettings();
    expect(s.baseUrl, 'https://api.deepseek.com');
    expect(s.model, 'deepseek-flash');
    expect(s.hasApiKey, isFalse);
  });
}
