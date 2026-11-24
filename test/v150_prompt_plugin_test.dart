import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/chat_source.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/models/prompt_plugin.dart';
import 'package:deepseek_chat/pages/plugin_settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/search_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/utils/prompt_assembler.dart';

/// v1.5.0：指令插件（提示词层）。
///
/// 所有「生效」断言都看最终 system prompt，而不是看界面文案。

class CapturingApi extends DeepSeekService {
  AppSettings? captured;

  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    captured = settings;
    yield const ChatChunk('好的');
    yield const ChatChunk('', done: true);
  }
}

class FakeSearch extends SearchService {
  FakeSearch({this.context = '资料条目'});

  final String context;
  bool? lastIncludeGuidance;

  @override
  Future<SearchOutcome> search({
    required String apiKey,
    required String query,
    String? oriQuestion,
    int count = AppSettings.defaultSearchCount,
    bool fetchContent = false,
    bool includeGuidance = true,
  }) async {
    lastIncludeGuidance = includeGuidance;
    return SearchOutcome(
      sources: const <ChatSource>[
        ChatSource(title: '来源', url: 'https://example.com'),
      ],
      contextText: includeGuidance ? '请优先依据资料\n$context' : context,
    );
  }

  @override
  void dispose() {}
}

PromptPlugin plugin(
  String id,
  String body, {
  bool enabled = true,
  int priority = 0,
  String name = '',
}) => PromptPlugin(
  id: id,
  name: name.isEmpty ? id : name,
  body: body,
  enabled: enabled,
  priority: priority,
);

void main() {
  group('拼装器', () {
    test('没有插件时与旧格式一致', () {
      final String prompt = PromptAssembler.build(
        plugins: const <PromptPlugin>[],
        dateLine: '时间行',
        basePrompt: '用户提示词',
        searchContext: '资料',
        overrideAppLines: false,
        model: 'deepseek-flash',
      );
      expect(prompt, '时间行\n\n用户提示词\n\n资料');
    });

    test('插件按 priority 排在时间行之前', () {
      final String prompt = PromptAssembler.build(
        plugins: <PromptPlugin>[
          plugin('b', '第二个', priority: 2),
          plugin('a', '第一个', priority: 1),
        ],
        dateLine: '时间行',
        basePrompt: '提示词',
        searchContext: '',
        overrideAppLines: false,
      );
      expect(prompt, '第一个\n\n第二个\n\n时间行\n\n提示词');
    });

    test('覆盖模式去掉时间行，保留用户提示词与资料', () {
      final String prompt = PromptAssembler.build(
        plugins: <PromptPlugin>[plugin('a', '破甲')],
        dateLine: '时间行',
        basePrompt: '提示词',
        searchContext: '资料',
        overrideAppLines: true,
      );
      expect(prompt, '破甲\n\n提示词\n\n资料');
      expect(prompt, isNot(contains('时间行')));
    });

    test('停用、空正文、超长单条都被处理', () {
      final String prompt = PromptAssembler.build(
        plugins: <PromptPlugin>[
          plugin('off', '停用的', enabled: false),
          plugin('empty', '   '),
          plugin('long', '长' * 5000),
        ],
        dateLine: '',
        basePrompt: '',
        searchContext: '',
        overrideAppLines: false,
      );
      expect(prompt.contains('停用的'), isFalse);
      expect(prompt.length, PromptPlugin.maxBodyChars);
    });

    test('超出总预算的插件被跳过', () {
      final String prompt = PromptAssembler.build(
        plugins: <PromptPlugin>[
          plugin('a', '甲' * 4000, priority: 1),
          plugin('b', '乙' * 4000, priority: 2),
          plugin('c', '丙', priority: 3),
        ],
        dateLine: '',
        basePrompt: '',
        searchContext: '',
        overrideAppLines: false,
      );
      expect(prompt.contains('甲'), isTrue);
      expect(prompt.contains('乙'), isTrue);
      expect(prompt.contains('丙'), isFalse);
    });

    test('变量替换，未知变量保留', () {
      final String prompt = PromptAssembler.build(
        plugins: <PromptPlugin>[
          plugin('a', '{{date}} {{time}} {{model}} {{unknown}}'),
        ],
        dateLine: '',
        basePrompt: '',
        searchContext: '',
        overrideAppLines: false,
        now: DateTime(2026, 1, 2, 3, 4),
        model: 'deepseek-flash',
      );
      expect(prompt, '2026-01-02 03:04 deepseek-flash {{unknown}}');
    });

    test('会话解析：null 跟随全局，空列表不用，指定只用子集', () {
      final AppSettings settings = AppSettings(
        plugins: <PromptPlugin>[
          plugin('a', 'A'),
          plugin('b', 'B'),
        ],
      );
      expect(PromptAssembler.resolve(settings, null).length, 2);
      expect(PromptAssembler.resolve(settings, <String>[]), isEmpty);
      expect(
        PromptAssembler.resolve(settings, <String>['b']).single.id,
        'b',
      );
    });
  });

  group('存储', () {
    test('设置 JSON 往返保留插件与覆盖开关', () {
      final AppSettings original = AppSettings(
        plugins: <PromptPlugin>[
          plugin('a', '破甲', priority: 2),
        ],
        pluginOverrideAppLines: true,
      );
      final AppSettings back = AppSettings.fromJson(original.toJson());
      expect(back.plugins.length, 1);
      expect(back.plugins.single.body, '破甲');
      expect(back.plugins.single.priority, 2);
      expect(back.pluginOverrideAppLines, isTrue);
    });

    test('旧数据没有插件字段时回到空列表', () {
      final AppSettings back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.plugins, isEmpty);
      expect(back.pluginOverrideAppLines, isFalse);
    });

    test('会话 JSON：null 不落盘，空列表要保留', () {
      final Conversation follow = Conversation(id: '1');
      expect(follow.toJson().containsKey('pluginIds'), isFalse);

      final Conversation none = Conversation(id: '2', pluginIds: <String>[]);
      expect(none.toJson()['pluginIds'], isEmpty);

      final Conversation some = Conversation(id: '3', pluginIds: <String>['a']);
      expect(
        Conversation.fromJson(some.toJson()).pluginIds,
        <String>['a'],
      );
    });
  });

  group('请求生效', () {
    Future<(ChatProvider, CapturingApi, FakeSearch)> ready({
      List<String>? sessionPluginIds,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService storage = StorageService(
        readKey: () async => null,
        writeKey: (String _) async {},
      );
      final CapturingApi api = CapturingApi();
      final FakeSearch fakeSearch = FakeSearch();
      final ChatProvider provider = ChatProvider(
        api: api,
        storage: storage,
        search: fakeSearch,
      );
      await provider.init();
      if (sessionPluginIds != null) {
        await provider.setActivePluginIds(sessionPluginIds);
      }
      return (provider, api, fakeSearch);
    }

    test('启用插件后 system prompt 以插件开头', () async {
      final (ChatProvider provider, CapturingApi api, _) = await ready();
      await provider.send(
        '你好',
        AppSettings(
          model: 'deepseek-flash',
          apiKey: 'k',
          plugins: <PromptPlugin>[plugin('a', '破冰指令')],
        ),
      );
      expect(api.captured!.systemPrompt, startsWith('破冰指令'));
    });

    test('没有插件时请求与旧行为一致', () async {
      final (ChatProvider provider, CapturingApi api, _) = await ready();
      await provider.send(
        '你好',
        AppSettings(model: 'deepseek-flash', apiKey: 'k'),
      );
      expect(api.captured!.systemPrompt, isNot(contains('破冰')));
      expect(api.captured!.systemPrompt, contains('当前时间是'));
    });

    test('覆盖模式去掉引导语，检索资料仍保留', () async {
      final (ChatProvider provider, CapturingApi api, FakeSearch search) =
          await ready();
      await provider.send(
        '你好',
        AppSettings(
          model: 'deepseek-flash',
          apiKey: 'k',
          plugins: <PromptPlugin>[plugin('a', '破冰指令')],
          pluginOverrideAppLines: true,
          searchEnabled: true,
          searchApiKey: 'k',
        ),
      );
      expect(search.lastIncludeGuidance, isFalse);
      expect(api.captured!.systemPrompt, contains('资料条目'));
      expect(api.captured!.systemPrompt, isNot(contains('请优先依据')));
      expect(api.captured!.systemPrompt, isNot(contains('当前时间是')));
    });

    test('本会话指定插件只对当前会话生效', () async {
      final (ChatProvider provider, CapturingApi api, _) = await ready(
        sessionPluginIds: <String>['b'],
      );
      await provider.send(
        '你好',
        AppSettings(
          model: 'deepseek-flash',
          apiKey: 'k',
          plugins: <PromptPlugin>[
            plugin('a', '甲插件'),
            plugin('b', '乙插件'),
          ],
        ),
      );
      expect(api.captured!.systemPrompt, contains('乙插件'));
      expect(api.captured!.systemPrompt, isNot(contains('甲插件')));
    });
  });

  group('界面', () {
    testWidgets('插件设置页可渲染', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService storage = StorageService(
        readKey: () async => null,
        writeKey: (String _) async {},
      );
      final AppSettingsProvider provider = AppSettingsProvider(
        storage: storage,
      );
      await provider.init();

      await tester.pumpWidget(
        ChangeNotifierProvider<AppSettingsProvider>.value(
          value: provider,
          child: const MaterialApp(home: PluginSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PluginSettingsPage), findsOneWidget);
      expect(
        find.text('指令插件').evaluate().isNotEmpty ||
            find.text('Instruction plugins').evaluate().isNotEmpty,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
