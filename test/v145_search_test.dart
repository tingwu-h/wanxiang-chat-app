import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/search_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/utils/search_query.dart';

Map<String, Object> result({
  required String title,
  required String url,
  required String summary,
  double? score,
}) => <String, Object>{
  'title': title,
  'url': url,
  'summary': summary,
  'snippet': '短摘要',
  'site_name': 'example',
  if (score != null) 'rerank_score': score,
};

void main() {
  group('检索词组装', () {
    test('自包含问题只搜当前句', () {
      expect(
        SearchQueryBuilder.build(
          current: '深蹲膝盖疼怎么办',
          previous: '练完胸之后背很酸',
        ),
        '深蹲膝盖疼怎么办',
      );
    });

    test('短追问补上一轮问题，当前句在前', () {
      expect(
        SearchQueryBuilder.build(current: '为什么', previous: '练完胸之后背很酸'),
        '为什么 练完胸之后背很酸',
      );
    });

    test('带追问语气的长句也补上下文', () {
      final String q = SearchQueryBuilder.build(
        current: '为什么呢，给我详细解释一下',
        previous: '练完胸之后背很酸',
      );
      expect(q, startsWith('为什么呢，给我详细解释一下'));
      expect(q, contains('练完胸之后背很酸'));
    });

    test('没有上一轮时原样使用当前句', () {
      expect(SearchQueryBuilder.build(current: '为什么'), '为什么');
    });

    test('合并结果不超过 128 字，且保留开头的当前句', () {
      final String previous = '这是一段很长的上一轮问题' * 20;
      final String q = SearchQueryBuilder.build(
        current: '为什么',
        previous: previous,
      );
      expect(q.length, SearchQueryBuilder.maxQueryLength);
      expect(q, startsWith('为什么'));
    });
  });

  group('搜索结果过滤', () {
    Future<SearchOutcome> searchWith(
      List<Map<String, Object>> results, {
      bool fetch = false,
    }) {
      final SearchService service = SearchService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/fetch')) {
            return http.Response(
              jsonEncode(<String, Object>{'title': 't', 'content': '正文'}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object>{'results': results}),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      return service.search(
        apiKey: 'k',
        query: 'q',
        fetchContent: fetch,
      );
    }

    test('低于 1.0 的结果被丢弃，其余保持顺序', () async {
      final SearchOutcome outcome = await searchWith(<Map<String, Object>>[
        result(title: '差', url: 'https://a.com', summary: 'a', score: .2),
        result(title: '好', url: 'https://b.com', summary: 'b', score: 2.4),
        result(title: '中', url: 'https://c.com', summary: 'c', score: 1.2),
      ]);
      expect(outcome.sources.map((s) => s.title), <String>['好', '中']);
      expect(outcome.contextText, contains('好'));
      expect(outcome.contextText, isNot(contains('差')));
    });

    test('全部低于阈值时回退，不假装没结果', () async {
      final SearchOutcome outcome = await searchWith(<Map<String, Object>>[
        result(title: 'A', url: 'https://a.com', summary: 'a', score: .2),
        result(title: 'B', url: 'https://b.com', summary: 'b', score: .3),
      ]);
      expect(outcome.sources.length, 2);
    });

    test('分数缺失时不过滤', () async {
      final SearchOutcome outcome = await searchWith(<Map<String, Object>>[
        result(title: 'A', url: 'https://a.com', summary: 'a'),
      ]);
      expect(outcome.sources.length, 1);
    });

    test('只注入前 3 条，来源列表保留更多', () async {
      final SearchOutcome outcome = await searchWith(<Map<String, Object>>[
        for (int i = 1; i <= 5; i++)
          result(
            title: 'T$i',
            url: 'https://$i.com',
            summary: 'S$i',
            score: 2,
          ),
      ]);
      expect(outcome.sources.length, 5);
      expect(outcome.contextText, contains('T1'));
      expect(outcome.contextText, contains('T3'));
      expect(outcome.contextText, isNot(contains('T4')));
    });

    test('上下文不超过 8000 字', () async {
      final SearchOutcome outcome = await searchWith(<Map<String, Object>>[
        for (int i = 1; i <= 3; i++)
          result(
            title: 'T$i',
            url: 'https://$i.com',
            summary: '长' * 5000,
            score: 2,
          ),
      ]);
      expect(outcome.contextText.length, lessThanOrEqualTo(8001));
    });

    test('抓取正文最多 2 条', () async {
      int fetchCalls = 0;
      final SearchService service = SearchService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/fetch')) {
            fetchCalls++;
            return http.Response(
              jsonEncode(<String, Object>{'content': '正文'}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object>{
              'results': <Map<String, Object>>[
                for (int i = 1; i <= 5; i++)
                  result(
                    title: 'T$i',
                    url: 'https://$i.com',
                    summary: 'S$i',
                    score: 2,
                  ),
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      await service.search(apiKey: 'k', query: 'q', fetchContent: true);
      expect(fetchCalls, 2);
    });

    test('单篇正文 3000 字，两篇都完整不被整体截断', () async {
      final SearchService service = SearchService(
        client: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/fetch')) {
            return http.Response(
              jsonEncode(<String, Object>{'content': '正' * 5000}),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(<String, Object>{
              'results': <Map<String, Object>>[
                for (int i = 1; i <= 2; i++)
                  result(
                    title: 'T$i',
                    url: 'https://$i.com',
                    summary: 'S$i',
                    score: 2,
                  ),
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final SearchOutcome outcome = await service.search(
        apiKey: 'k',
        query: 'q',
        fetchContent: true,
      );

      final Iterable<RegExpMatch> bodies = RegExp(
        r'正文节选: (正+)',
      ).allMatches(outcome.contextText);
      expect(bodies.length, 2, reason: '两篇正文都应该留下');
      for (final RegExpMatch match in bodies) {
        expect(match.group(1)!.length, 3000);
      }
      expect(outcome.contextText.contains('正' * 3001), isFalse);
    });

    test('超时预算按保守值配置', () {
      expect(SearchService.searchTimeout, const Duration(seconds: 20));
      expect(SearchService.fetchTimeout, const Duration(seconds: 10));
      expect(SearchService.maxFetches, 2);
      expect(SearchService.maxInjectedSources, 3);
    });
  });

  group('结束原因与空正文', () {
    Future<ChatProvider> providerWithSse(String sse) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService storage = StorageService(
        readKey: () async => null,
        writeKey: (String _) async {},
      );
      final DeepSeekService api = DeepSeekService(
        client: MockClient.streaming((
          http.BaseRequest request,
          http.ByteStream bodyStream,
        ) async {
          await bodyStream.bytesToString();
          return http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode(sse)),
            200,
            headers: <String, String>{'content-type': 'text/event-stream'},
          );
        }),
      );
      final ChatProvider provider = ChatProvider(api: api, storage: storage);
      await provider.init();
      return provider;
    }

    Future<void> send(ChatProvider provider) => provider.send(
      '为什么我练完胸之后背很酸',
      AppSettings(model: 'deepseek-flash', apiKey: 'k'),
    );

    test('aborted + 只有思考 → 明确失败', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{"reasoning_content":"想一想"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"aborted"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isTrue);
      expect(msg.content, contains('中断'));
    });

    test('insufficient_system_resource 没有正文 → 明确失败', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{},"finish_reason":"insufficient_system_resource"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isTrue);
      expect(msg.content, contains('资源不足'));
    });

    test('length + 部分正文 → 保留正文并提示截断', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{"content":"已经写了一些"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isFalse);
      expect(msg.content, contains('已经写了一些'));
      expect(msg.content, contains('截断'));
    });

    test('content_filter 且无正文 → 明确失败', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{},"finish_reason":"content_filter"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isTrue);
      expect(msg.content, contains('过滤'));
    });

    test('只有思考、finish_reason=stop → 不再静默留空', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{"reasoning_content":"想了很久"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isTrue);
      expect(msg.content, contains('只输出了思考过程'));
    });

    test('正常回答不受影响', () async {
      final ChatProvider provider = await providerWithSse(
        'data: {"choices":[{"delta":{"content":"正常回答"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
      );
      await send(provider);
      final msg = provider.conversations.first.messages.last;
      expect(msg.error, isFalse);
      expect(msg.content, '正常回答');
    });
  });
}
