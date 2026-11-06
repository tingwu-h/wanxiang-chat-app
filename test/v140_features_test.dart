import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/chat_source.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/api_protocol.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/search_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';

/// v1.4.0：验证每个开关「可选 / 可存 / 真正生效」。
///
/// 「真正生效」一律断言**不发 UI、不断言界面文案**，而是断言
/// 实际请求体或实际行为变化——这样才能抓出「开关只是摆设」的问题。

class FakeSearch extends SearchService {
  FakeSearch({this.outcome, this.error});

  final SearchOutcome? outcome;
  final Object? error;

  int calls = 0;
  bool? lastFetch;
  int? lastCount;
  String? lastQuery;

  @override
  Future<SearchOutcome> search({
    required String apiKey,
    required String query,
    String? oriQuestion,
    int count = AppSettings.defaultSearchCount,
    bool fetchContent = false,
  }) async {
    calls++;
    lastQuery = query;
    lastCount = count;
    lastFetch = fetchContent;
    if (error != null) throw error!;
    return outcome ??
        const SearchOutcome(
          sources: <ChatSource>[],
          contextText: '',
        );
  }

  @override
  void dispose() {}
}

class SilentApi extends DeepSeekService {
  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    yield const ChatChunk('好的');
    yield const ChatChunk('', done: true);
  }
}

Future<ChatProvider> providerWith(
  SearchService search, {
  StorageService? storage,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final ChatProvider p = ChatProvider(
    api: SilentApi(),
    storage: storage ?? StorageService(),
    search: search,
  );
  await p.init();
  return p;
}

void main() {
  group('① 可选 & ② 可存：新增设置项', () {
    test('默认值符合预期（联网关、来源显示开、思考模式开、effort=high）', () {
      final AppSettings s = AppSettings();
      expect(s.searchEnabled, isFalse);
      expect(s.searchCount, AppSettings.defaultSearchCount);
      expect(s.searchFetch, isFalse);
      expect(s.showSources, isTrue);
      expect(s.thinkingEnabled, isTrue);
      expect(s.reasoningEffort, 'high');
      expect(s.imageDetail, '');
    });

    test('JSON 往返保留全部新字段', () {
      final AppSettings s = AppSettings(
        searchEnabled: true,
        searchApiKey: 'sk-search',
        searchCount: 7,
        searchFetch: true,
        showSources: false,
        thinkingEnabled: false,
        reasoningEffort: 'max',
        imageDetail: 'low',
      );
      final AppSettings back = AppSettings.fromJson(s.toJson());
      expect(back.searchEnabled, isTrue);
      expect(back.searchApiKey, 'sk-search');
      expect(back.searchCount, 7);
      expect(back.searchFetch, isTrue);
      expect(back.showSources, isFalse);
      expect(back.thinkingEnabled, isFalse);
      expect(back.reasoningEffort, 'max');
      expect(back.imageDetail, 'low');
    });

    test('旧数据缺字段时安全回落', () {
      final AppSettings back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.searchEnabled, isFalse);
      expect(back.showSources, isTrue);
      expect(back.thinkingEnabled, isTrue);
      expect(back.reasoningEffort, 'high');
    });

    test('结果条数越界被夹到 1~50', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{'searchCount': 0}).searchCount,
        AppSettings.minSearchCount,
      );
      expect(
        AppSettings.fromJson(<String, dynamic>{'searchCount': 999}).searchCount,
        AppSettings.maxSearchCount,
      );
    });

    test('切换服务商不丢联网与思考设置（应用级设置）', () {
      final AppSettings s = AppSettings(
        searchEnabled: true,
        searchCount: 9,
        searchFetch: true,
        showSources: false,
        thinkingEnabled: false,
        reasoningEffort: 'low',
        imageDetail: 'low',
      );
      final AppSettings other = s.forProvider('openai');
      expect(other.searchEnabled, isTrue);
      expect(other.searchCount, 9);
      expect(other.searchFetch, isTrue);
      expect(other.showSources, isFalse);
      expect(other.thinkingEnabled, isFalse);
      expect(other.reasoningEffort, 'low');
      expect(other.imageDetail, 'low');
    });
  });

  group('③ 真正生效：联网开关', () {
    test('开启时确实调用搜索，且条数/抓正文参数被透传', () async {
      final FakeSearch search = FakeSearch(
        outcome: const SearchOutcome(
          sources: <ChatSource>[
            ChatSource(title: '标题A', url: 'https://a.example/x', snippet: '摘要A'),
          ],
          contextText: '检索资料内容',
        ),
      );
      final ChatProvider p = await providerWith(search);
      await p.send(
        '今天有什么新闻',
        AppSettings(
          apiKey: 'k',
          searchEnabled: true,
          searchCount: 3,
          searchFetch: true,
        ),
      );

      expect(search.calls, 1, reason: '开关打开必须真的发起搜索');
      expect(search.lastCount, 3);
      expect(search.lastFetch, isTrue);
      expect(p.messages.last.sources.length, 1, reason: '来源要挂到这条回答上');
    });

    test('关闭时一次都不调用搜索', () async {
      final FakeSearch search = FakeSearch();
      final ChatProvider p = await providerWith(search);
      await p.send('随便问问', AppSettings(apiKey: 'k', searchEnabled: false));
      expect(search.calls, 0, reason: '关闭后不能偷偷联网');
    });

    test('没配 Key 时不调用搜索，且给出提示', () async {
      final FakeSearch search = FakeSearch();
      final ChatProvider p = await providerWith(search);
      await p.send(
        '问题',
        AppSettings(providerId: 'openai', apiKey: '', searchEnabled: true),
      );
      expect(search.calls, 0);
      expect(p.error, contains('未联网'));
    });

    test('搜索失败时降级为无联网回答（不阻断回答）', () async {
      final FakeSearch search = FakeSearch(
        error: DeepSeekException('429 限流'),
      );
      final ChatProvider p = await providerWith(search);
      await p.send('问题', AppSettings(apiKey: 'k', searchEnabled: true));

      final ChatMessage last = p.messages.last;
      expect(last.content, contains('好的'), reason: '搜索失败仍要能回答');
      expect(last.error, isFalse, reason: '不能把回答标成失败');
    });

    test('搜索用的 Key：默认复用 DeepSeek 那家的 Key', () {
      final AppSettings s = AppSettings(
        providerId: 'openai',
        apiKey: 'sk-openai',
        profiles: <String, Map<String, dynamic>>{
          'deepseek': <String, dynamic>{'apiKey': 'sk-deepseek'},
        },
      );
      expect(s.effectiveSearchApiKey, 'sk-deepseek');
      expect(s.canSearch, isTrue);
    });

    test('搜索专用 Key 优先于服务商 Key', () {
      final AppSettings s = AppSettings(
        apiKey: 'sk-main',
        searchApiKey: 'sk-own',
      );
      expect(s.effectiveSearchApiKey, 'sk-own');
    });
  });

  group('③ 真正生效：思考模式 / 推理强度 / 温度', () {
    test('思考关闭时请求体带 disabled', () {
      final Map<String, dynamic> body = ApiProtocol.body(
        AppSettings(model: 'deepseek-flash', thinkingEnabled: false),
        <Map<String, dynamic>>[],
        true,
      );
      expect((body['thinking'] as Map)['type'], 'disabled');
    });

    test('思考开启时请求体带 enabled 与推理强度', () {
      final Map<String, dynamic> body = ApiProtocol.body(
        AppSettings(
          model: 'deepseek-flash',
          thinkingEnabled: true,
          reasoningEffort: 'max',
        ),
        <Map<String, dynamic>>[],
        true,
      );
      expect((body['thinking'] as Map)['type'], 'enabled');
      expect(body['reasoning_effort'], 'max');
    });

    test('思考模式下不发送 temperature（官方说明此时无效）', () {
      final Map<String, dynamic> body = ApiProtocol.body(
        AppSettings(
          model: 'deepseek-flash',
          thinkingEnabled: true,
          temperature: 1.7,
        ),
        <Map<String, dynamic>>[],
        true,
      );
      expect(body.containsKey('temperature'), isFalse);
    });

    test('关闭思考后 temperature 恢复生效', () {
      final Map<String, dynamic> body = ApiProtocol.body(
        AppSettings(
          model: 'deepseek-flash',
          thinkingEnabled: false,
          temperature: 1.7,
        ),
        <Map<String, dynamic>>[],
        true,
      );
      expect(body['temperature'], 1.7);
    });

    test('非 DeepSeek 服务商不受思考开关影响', () {
      final Map<String, dynamic> body = ApiProtocol.body(
        AppSettings(providerId: 'kimi', model: 'kimi-k2.5'),
        <Map<String, dynamic>>[],
        true,
      );
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('③ 真正生效：图片细节档位', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('wx-detail-');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('detail=low 会写进 image_url 块', () async {
      final File f = File('${temp.path}/a.png');
      await f.writeAsBytes(<int>[137, 80, 78, 71, 1, 2, 3]);
      final ChatMessage m = ChatMessage.user(
        '看图',
        attachments: <ChatAttachment>[
          ChatAttachment(
            name: 'a.png',
            path: f.path,
            kind: 'image',
            size: await f.length(),
          ),
        ],
      );
      final Map<String, dynamic> json = await m.toApiJsonWithAttachments(
        imageDetail: 'low',
      );
      final List<dynamic> blocks = json['content'] as List<dynamic>;
      final Map<String, dynamic> img = blocks
          .whereType<Map<String, dynamic>>()
          .firstWhere((Map<String, dynamic> b) => b['type'] == 'image_url');
      expect((img['image_url'] as Map)['detail'], 'low');
    });

    test('不设档位时不发送 detail 字段', () async {
      final File f = File('${temp.path}/b.png');
      await f.writeAsBytes(<int>[137, 80, 78, 71, 9]);
      final ChatMessage m = ChatMessage.user(
        '看图',
        attachments: <ChatAttachment>[
          ChatAttachment(
            name: 'b.png',
            path: f.path,
            kind: 'image',
            size: await f.length(),
          ),
        ],
      );
      final Map<String, dynamic> json = await m.toApiJsonWithAttachments();
      final List<dynamic> blocks = json['content'] as List<dynamic>;
      final Map<String, dynamic> img = blocks
          .whereType<Map<String, dynamic>>()
          .firstWhere((Map<String, dynamic> b) => b['type'] == 'image_url');
      expect((img['image_url'] as Map).containsKey('detail'), isFalse);
    });
  });

  group('③ 真正生效：每会话提示词', () {
    test('会话提示词优先于全局默认', () async {
      final ChatProvider p = await providerWith(FakeSearch());
      await p.setActiveSystemPrompt('你是猫娘');
      expect(p.effectiveSystemPrompt(AppSettings(systemPrompt: '全局默认')), '你是猫娘');
    });

    test('会话为空时回落到全局默认', () async {
      final ChatProvider p = await providerWith(FakeSearch());
      await p.setActiveSystemPrompt('');
      expect(p.effectiveSystemPrompt(AppSettings(systemPrompt: '全局默认')), '全局默认');
    });

    test('两个会话的提示词互不影响', () async {
      final ChatProvider p = await providerWith(FakeSearch());
      // 先发一条消息，否则空会话点「新建」不会真的新建
      await p.send('A 的问题', AppSettings(apiKey: 'k'));
      await p.setActiveSystemPrompt('A 的提示词');
      final String idA = p.activeConversationId!;

      await p.newConversation();
      await p.setActiveSystemPrompt('B 的提示词');

      expect(p.activeSystemPrompt, 'B 的提示词');
      await p.switchConversation(idA);
      expect(p.activeSystemPrompt, 'A 的提示词');
    });

    test('提示词会持久化，重载后仍在', () async {
      final StorageService storage = StorageService();
      final ChatProvider p = await providerWith(FakeSearch(), storage: storage);
      await p.setActiveSystemPrompt('持久化的提示词');
      final String id = p.activeConversationId!;

      final ChatProvider reloaded = ChatProvider(
        api: SilentApi(),
        storage: storage,
        search: FakeSearch(),
      );
      await reloaded.init();
      await reloaded.switchConversation(id);
      expect(reloaded.activeSystemPrompt, '持久化的提示词');
    });

    test('Conversation JSON 往返保留 systemPrompt；旧数据读成 null', () {
      final Conversation c = Conversation(id: 'x')
        ..systemPrompt = '自定义';
      final Conversation back = Conversation.fromJson(c.toJson());
      expect(back.systemPrompt, '自定义');

      final Conversation old = Conversation.fromJson(<String, dynamic>{
        'id': 'y',
        'messages': <dynamic>[],
      });
      expect(old.systemPrompt, isNull);
      expect(old.hasOwnSystemPrompt, isFalse);
    });
  });

  group('③ 真正生效：来源显示开关', () {
    Widget bubble({required bool showSources}) => MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: (ChatMessage.assistant('回答')
                ..sources = <ChatSource>[
                  const ChatSource(title: '来源标题', url: 'https://e.example/p'),
                ]),
          showSources: showSources,
        ),
      ),
    );

    testWidgets('开启时显示可展开的来源标题（默认收起，不铺开列表）',
        (WidgetTester tester) async {
      await tester.pumpWidget(bubble(showSources: true));
      // 默认收起：只有一行可点的标题（用展开箭头判断，避免依赖语言）
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.textContaining('来源标题'), findsNothing);

      // 点一下才展开
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
      expect(find.textContaining('来源标题'), findsOneWidget);
      // 展开后箭头翻转
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('关闭时不渲染来源', (WidgetTester tester) async {
      await tester.pumpWidget(bubble(showSources: false));
      expect(find.textContaining('来源标题'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });
  });

  group('搜索服务：请求与解析', () {
    test('请求体带上 query / count / ori_question，且不请求正文', () async {
      late Map<String, dynamic> sent;
      final http.Client client = _FakeClient((http.BaseRequest req) {
        sent = jsonDecode((req as http.Request).body) as Map<String, dynamic>;
        // 用 bytes 构造，否则中文会被按 latin1 编码而报错
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'results': <dynamic>[
                <String, dynamic>{
                  'title': 'T1',
                  'url': 'https://x.example/1',
                  'snippet': 'S1',
                  'summary': '长摘要 1',
                },
              ],
            }),
          ),
          200,
        );
      });
      final SearchService svc = SearchService(client: client);
      final SearchOutcome out = await svc.search(
        apiKey: 'k',
        query: '查询词',
        oriQuestion: '原始问题',
        count: 4,
      );

      expect(sent['query'], '查询词');
      expect(sent['ori_question'], '原始问题');
      expect(sent['count'], 4);
      expect(sent['need_content'], isFalse);
      expect(out.sources.length, 1);
      expect(out.contextText, contains('https://x.example/1'));
      expect(out.contextText, contains('长摘要 1'));
      svc.dispose();
    });

    test('401 会翻译成可读提示', () async {
      final SearchService svc = SearchService(
        client: _FakeClient(
          (_) => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{'message': 'bad key'},
            }),
            401,
          ),
        ),
      );
      await expectLater(
        svc.search(apiKey: 'k', query: 'q'),
        throwsA(
          isA<DeepSeekException>().having(
            (DeepSeekException e) => e.message,
            'message',
            contains('401'),
          ),
        ),
      );
      svc.dispose();
    });

    test('空 Key 直接报错，不发请求', () async {
      bool called = false;
      final SearchService svc = SearchService(
        client: _FakeClient((_) {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        svc.search(apiKey: '', query: 'q'),
        throwsA(isA<DeepSeekException>()),
      );
      expect(called, isFalse);
      svc.dispose();
    });
  });
}

/// 只实现 post 的假客户端
class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);
  final http.Response Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Response res = handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}
