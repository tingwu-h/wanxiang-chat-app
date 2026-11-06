import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/chat_source.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';

/// 一次联网检索的结果：既给模型用（[contextText]），也给界面用（[sources]）。
class SearchOutcome {
  const SearchOutcome({
    required this.sources,
    required this.contextText,
    this.fetchedCount = 0,
  });

  final List<ChatSource> sources;

  /// 拼进 system 提示词的检索资料；为空表示没有可用结果
  final String contextText;

  /// 实际抓取正文的条数（0 表示只用摘要）
  final int fetchedCount;

  bool get isEmpty => sources.isEmpty;
}

/// DeepSeek 官方 Search / Fetch 封装。
///
/// 为什么单独成一个服务：
/// - 这两个接口与「当前对话用的是哪家模型」无关，
///   所以换 OpenAI / Kimi / Qwen 等模型时联网依然可用。
/// - 官方按**成功请求次数**计费（$0.75/千次），与 token 无关，
///   因此调用次数要由用户显式开关控制，不能悄悄调用。
///
/// 文档：https://api-docs.deepseek.com/guides/search
class SearchService {
  SearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String searchPath = '/v1/tools/search';
  static const String fetchPath = '/v1/tools/fetch';

  /// 单条网页正文最多取这么多字，避免把上下文撑爆
  static const int maxContentChars = 4000;

  /// 拼进提示词的检索资料总字数上限
  static const int maxContextChars = 12000;

  void dispose() => _client.close();

  /// 执行一次检索。
  ///
  /// [fetchContent] 为 true 时会对前若干条结果再调 Fetch 抓正文
  /// （每条 = 一次额外计费请求）。
  Future<SearchOutcome> search({
    required String apiKey,
    required String query,
    String? oriQuestion,
    int count = AppSettings.defaultSearchCount,
    bool fetchContent = false,
  }) async {
    final String key = apiKey.trim();
    if (key.isEmpty) {
      throw DeepSeekException(
        '联网搜索需要 DeepSeek API Key，请先在设置里填写。',
        failureKind: MessageFailure.provider,
      );
    }
    final String q = query.trim();
    if (q.isEmpty) {
      return const SearchOutcome(sources: <ChatSource>[], contextText: '');
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'query': q.length > 128 ? q.substring(0, 128) : q,
      'count': count.clamp(
        AppSettings.minSearchCount,
        AppSettings.maxSearchCount,
      ),
      if (oriQuestion != null && oriQuestion.trim().isNotEmpty)
        'ori_question': oriQuestion.trim().length > 128
            ? oriQuestion.trim().substring(0, 128)
            : oriQuestion.trim(),
      // 正文单独用 Fetch 取，这里只要摘要，响应更小
      'need_content': false,
    };

    final Map<String, dynamic> json = await _post(key, searchPath, payload);

    final List<ChatSource> sources = <ChatSource>[];
    final List<String> summaries = <String>[];
    final Object? results = json['results'];
    if (results is List) {
      for (final Object? item in results) {
        if (item is! Map) continue;
        final String url = (item['url'] as String?) ?? '';
        if (url.trim().isEmpty) continue;
        final String title = (item['title'] as String?) ?? '';
        // 官方说明 summary 是给模型读的长摘要，优先用它
        final String summary = (item['summary'] as String?) ?? '';
        final String snippet = (item['snippet'] as String?) ?? '';
        final String siteName = (item['site_name'] as String?) ?? '';
        sources.add(
          ChatSource(
            title: title,
            url: url,
            snippet: snippet.isNotEmpty ? snippet : summary,
            siteName: siteName,
          ),
        );
        summaries.add(
          summary.isNotEmpty ? summary : (snippet.isNotEmpty ? snippet : title),
        );
      }
    }

    if (sources.isEmpty) {
      return const SearchOutcome(sources: <ChatSource>[], contextText: '');
    }

    int fetched = 0;
    final List<String> bodies = <String>[];
    if (fetchContent) {
      // 只抓前 N 条，且允许个别失败（抓不到就退回摘要）
      final int limit = sources.length < 3 ? sources.length : 3;
      for (int i = 0; i < limit; i++) {
        try {
          final Map<String, dynamic> page = await _post(key, fetchPath, {
            'url': sources[i].url,
          });
          final String content = (page['content'] as String?) ?? '';
          if (content.trim().isNotEmpty) {
            bodies.add(_truncate(content.trim(), maxContentChars));
            fetched++;
          }
        } catch (_) {
          // 单条抓取失败不应让整次联网失败
        }
      }
    }

    final StringBuffer sb = StringBuffer();
    sb.writeln('以下是我刚检索到的网页资料，请优先依据它们回答。');
    sb.writeln('要求：');
    sb.writeln('1. 用 [编号] 标注引用来源，例如「据 [1] 报道…」。');
    sb.writeln('2. 资料不足时明确说明不知道，不要编造。');
    sb.writeln();
    for (int i = 0; i < sources.length; i++) {
      sb.writeln('[${i + 1}] ${sources[i].displayTitle}');
      sb.writeln('URL: ${sources[i].url}');
      if (i < bodies.length && bodies[i].isNotEmpty) {
        sb.writeln('正文节选: ${bodies[i]}');
      } else {
        sb.writeln('摘要: ${summaries[i]}');
      }
      sb.writeln();
    }

    return SearchOutcome(
      sources: sources,
      contextText: _truncate(sb.toString().trim(), maxContextChars),
      fetchedCount: fetched,
    );
  }

  Future<Map<String, dynamic>> _post(
    String apiKey,
    String path,
    Map<String, dynamic> body,
  ) async {
    final Uri uri = Uri.parse('${AppSettings.searchBaseUrl}$path');
    final List<int> bytes = utf8.encode(jsonEncode(body));

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: bytes,
          )
          .timeout(DeepSeekService.connectTimeout);
    } on TimeoutException {
      throw DeepSeekException(
        '联网搜索超时，请稍后重试。',
        failureKind: MessageFailure.timeout,
      );
    } on SocketException {
      throw DeepSeekException(
        '联网搜索时网络不可用，请检查网络。',
        failureKind: MessageFailure.network,
      );
    } on http.ClientException {
      throw DeepSeekException(
        '联网搜索连接失败，请检查网络。',
        failureKind: MessageFailure.network,
      );
    }

    final String raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw DeepSeekException(
        _friendlyError(response.statusCode, raw),
        statusCode: response.statusCode,
        failureKind: MessageFailure.provider,
      );
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      throw DeepSeekException(
        '搜索服务返回了无法识别的数据。',
        failureKind: MessageFailure.provider,
      );
    } on FormatException {
      throw DeepSeekException(
        '搜索服务返回了无法识别的数据。',
        failureKind: MessageFailure.provider,
      );
    }
  }

  /// 官方错误码含义（见 Search & Fetch 文档）
  String _friendlyError(int status, String raw) {
    String detail = '';
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map && decoded['error'] is Map) {
        final Object? msg = (decoded['error'] as Map)['message'];
        if (msg is String) detail = msg;
      }
    } catch (_) {
      detail = raw.length > 160 ? raw.substring(0, 160) : raw;
    }
    final String prefix = switch (status) {
      401 => '搜索用的 API Key 无效或已过期（401）',
      402 => '账户余额不足，无法使用搜索（402）',
      403 => '搜索请求被安全策略拒绝（403）',
      404 => '搜索服务找不到内容（404）',
      408 => '搜索请求超时（408）',
      413 => '搜索请求体过大（413）',
      429 => '搜索请求过于频繁，请稍后重试（429）',
      500 || 504 => '搜索服务暂时不可用（$status）',
      _ => '搜索失败（$status）',
    };
    return detail.isEmpty ? prefix : '$prefix：$detail';
  }

  static String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';
}
