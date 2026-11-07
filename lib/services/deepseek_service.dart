import 'package:deepseek_chat/services/api_protocol.dart';
import 'package:deepseek_chat/models/provider_catalog.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/services/attachment_service.dart';

/// 流式返回的一小段内容。
class ChatChunk {
  const ChatChunk(
    this.text, {
    this.thinking = false,
    this.done = false,
    this.finishReason,
  });
  final bool done;

  /// 本段的文字（可能为空串，例如只带 finish_reason 的最后一帧）
  final String text;

  /// 是否是 `deepseek-reasoner` 的思维链（reasoning_content）
  final bool thinking;

  /// 服务端结束原因：stop / length / content_filter / aborted /
  /// insufficient_system_resource。拿到它才能区分“正常结束”和“被中断”。
  final String? finishReason;

  bool get isEmpty => text.isEmpty;
}

/// 调用失败的异常，`message` 已经是可以直接展示给用户的中文提示。
class DeepSeekException implements Exception {
  DeepSeekException(this.message, {this.statusCode, this.failureKind});

  final String message;
  final int? statusCode;

  /// 失败类别（见 [MessageFailure]）。
  ///
  /// 由抛出处按已知信息直接标明，比事后猜异常类型更准：
  /// 例如同一个 DeepSeekException 既可能是服务商 5xx，也可能是本地参数校验。
  final String? failureKind;

  @override
  String toString() => message;
}

/// 把底层异常归到 [MessageFailure] 三类之一。
///
/// 放在这里而不是 Provider 里，是因为只有服务层知道请求是怎么发的
/// （比如 http 会把 SocketException 包进 ClientException）。
String classifyFailure(Object error) {
  if (error is DeepSeekException) {
    return error.failureKind ?? MessageFailure.provider;
  }
  if (error is TimeoutException) return MessageFailure.timeout;

  // http 客户端会把底层 socket 错误包成 ClientException，
  // 所以要连 cause 一起看，否则网络问题会被误判成服务商问题。
  Object? probe = error;
  for (int depth = 0; depth < 4 && probe != null; depth++) {
    if (probe is SocketException ||
        probe is HandshakeException ||
        probe is HttpException ||
        probe is http.ClientException) {
      return MessageFailure.network;
    }
    probe = probe is Error ? null : _causeOf(probe);
  }
  return MessageFailure.provider;
}

/// 尽量取出异常的 cause（没有就返回 null）
Object? _causeOf(Object error) {
  try {
    final dynamic d = error;
    return d.cause as Object?;
  } catch (_) {
    return null;
  }
}

/// DeepSeek API 封装：`POST {baseUrl}/chat/completions`（OpenAI 兼容格式）。
///
/// 同时实现了：
/// - `stream: true` 的 SSE 逐字返回（打字机效果）
/// - 兼容流式端点返回普通 JSON；连接测试使用非流式请求
abstract interface class ChatService {
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  });
  Future<String> completeChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  });
  Future<String> testConnection(AppSettings settings);
  void cancel();
  void dispose();
}

class DeepSeekService implements ChatService {
  DeepSeekService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Completer<void>? _abort;

  @override
  void cancel() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  /// 建立连接（拿到响应头）的最长等待时间。
  static const Duration connectTimeout = Duration(seconds: 60);

  /// 连续「一个字节都没收到」多久算连接已死。
  ///
  /// 为什么是 180 秒：必须比任何正常的慢回答都宽松。
  /// 只要服务端还在发数据（哪怕很慢），这个计时就会被重置，
  /// 所以它**只**能抓住"连接彻底没响应"这一种情况。
  ///
  /// 刻意不设"多久没内容就失败"那种超时：服务端发心跳却没内容时，
  /// 从网络层看和慢回答完全一样，设了必然误杀慢回答。
  static const Duration silenceTimeout = Duration(seconds: 180);

  @override
  void dispose() {
    cancel();
    _client.close();
  }

  static Uri endpoint(String baseUrl) {
    String base = baseUrl.trim();
    if (base.isEmpty) base = AppSettings.defaultBaseUrl;
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    // 允许用户直接粘贴 ".../chat/completions" 或 ".../v1"
    final int idx = base.indexOf('/chat/completions');
    if (idx >= 0) base = base.substring(0, idx);
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.parse('$base/chat/completions');
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw DeepSeekException('请输入有效的 HTTPS 接口地址，避免泄露密钥。');
    }
    return uri;
  }

  static bool supportsImages(String model) => modelSupportsImages(model);

  static void validateImages(String model, List<ChatMessage> history) {
    if (!supportsImages(model) &&
        history.any((m) => !m.error && m.attachments.any((a) => a.isImage))) {
      throw DeepSeekException('这个对话包含图片，请切换到支持图片的模型后发送，或新建纯文字对话。');
    }
  }

  /// 把 UI 上的消息整理成 API 需要的 `messages`。
  ///
  /// - 过滤错误气泡、空消息
  /// - 带附件的消息会拼成 block 数组（图片 → image_url，文本文件 → text）
  /// - 官方要求：图片只能出现在 user 消息里，这里天然满足（附件只挂在用户消息上）
  ///
  /// 注意：因为要读图片文件并转 base64，这个方法是异步的。
  Future<List<Map<String, dynamic>>> buildApiMessages(
    List<ChatMessage> history, {
    String? systemPrompt,
    String imageDetail = '',
  }) async {
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    final attachments = history
        .where((m) => !m.error)
        .expand((m) => m.attachments)
        .toList();
    int actualSize = 0;
    for (final a in attachments) {
      if (a.isImage) {
        final file = File(a.path);
        if (!await file.exists()) {
          throw DeepSeekException('图片 ${a.name} 已丢失，请重新添加或新建对话。');
        }
        final size = await file.length();
        if (size > AttachmentService.maxImageBytes) {
          throw DeepSeekException('图片 ${a.name} 超过 5 MB，请缩小后再发送。');
        }
        actualSize += size;
      } else {
        actualSize += utf8.encode(a.textContent ?? '').length;
      }
    }
    if (actualSize > AttachmentService.maxTotalBytes) {
      throw DeepSeekException('这个对话的附件合计超过 15 MB，请新建对话继续。');
    }
    final String sys = (systemPrompt ?? '').trim();
    if (sys.isNotEmpty) {
      result.add(<String, dynamic>{'role': MessageRole.system, 'content': sys});
    }
    for (final ChatMessage m in history) {
      if (m.error) continue;
      if (m.isBlank) continue;
      if (m.isAssistant && m.content.trim().isEmpty) continue;
      if (m.attachments.isEmpty) {
        result.add(m.toApiJson());
      } else {
        result.add(
          await m.toApiJsonWithAttachments(imageDetail: imageDetail),
        );
      }
    }
    return result;
  }

  // --------------------------------------------------------------- 流式请求

  /// 边收边吐的流式接口。
  ///
  /// 用法：
  /// ```dart
  /// await for (final chunk in service.streamChat(...)) {
  ///   setState(() => text += chunk.text);
  /// }
  /// ```
  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    if (settings.model.trim().isEmpty || settings.baseUrl.trim().isEmpty) {
      throw DeepSeekException('请先填写模型名称和 API 接口地址。');
    }
    cancel();
    final abort = Completer<void>();
    _abort = abort;
    final String apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw DeepSeekException('还没有填写 API Key，请先到「设置」里填写。');
    }

    final Uri uri = ApiProtocol.endpoint(settings, stream: true);
    if (!settings.supportsImages &&
        history.any((m) => !m.error && m.attachments.any((a) => a.isImage))) {
      throw DeepSeekException('当前模型未启用图片支持，请更换模型或在设置中确认图片能力。');
    }
    final List<Map<String, dynamic>> messages = await buildApiMessages(
      history,
      systemPrompt: settings.systemPrompt,
      imageDetail: settings.imageDetail,
    );
    if (messages.isEmpty) {
      throw DeepSeekException('没有可发送的内容。');
    }

    if (abort.isCompleted) return;
    final http.Request request =
        http.AbortableRequest('POST', uri, abortTrigger: abort.future)
          ..headers.addAll(ApiProtocol.headers(settings))
          ..body = jsonEncode(ApiProtocol.body(settings, messages, true));
    if (request.bodyBytes.length > 24 * 1024 * 1024) {
      throw DeepSeekException('对话附件过多，请新建对话或减少图片后再发送。');
    }

    // 建连超时单独捕获：它和"连上后长时间没数据"要给不同提示，
    // 否则用户不知道该查网络还是该等模型。
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(connectTimeout);
    } on TimeoutException {
      throw DeepSeekException(
        '连接 ${presetFor(settings.providerId).name} 超时（已等待 ${connectTimeout.inSeconds} 秒）。'
        '请检查网络后重试。',
        failureKind: MessageFailure.timeout,
      );
    }

    // 服务端直接报错（401 / 402 / 429 ...）：把 JSON 里的 message 读出来
    if (response.statusCode != 200) {
      final String raw = await response.stream.bytesToString().timeout(silenceTimeout);
      throw DeepSeekException(
        _friendlyError(response.statusCode, raw),
        statusCode: response.statusCode,
        failureKind: MessageFailure.provider,
      );
    }

    // Some compatible services respond with ordinary JSON even when stream=true.
    // Consume that response once; never resend a billable request automatically.
    if ((response.headers['content-type'] ?? '').contains('application/json')) {
      final raw = await response.stream.bytesToString().timeout(silenceTimeout);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (settings.protocol != 'openai') {
        for (final (text, thinking, done) in ApiProtocol.decode(
          settings.protocol,
          json,
          full: true,
        )) {
          yield ChatChunk(text, thinking: thinking, done: done);
        }
        return;
      }
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw DeepSeekException('服务端没有返回有效回答，请检查接口配置。');
      }
      final message = choices.first['message'] as Map<String, dynamic>;
      final thinking = message['reasoning_content'];
      if (thinking is String && thinking.isNotEmpty) {
        yield ChatChunk(thinking, thinking: true);
      }
      final String content = message['content'] as String? ?? '';
      if (content.isNotEmpty) yield ChatChunk(content);
      final Object? finish = choices.first['finish_reason'];
      if (finish is String && finish.isNotEmpty) {
        yield ChatChunk('', finishReason: finish);
      }
      return;
    }

    // ---------- 增量解析 SSE ----------
    // 注意：必须用 utf8.decoder 而不是 response.stream.transform(utf8.decoder)
    // 的简写形式在多字节字符（中文）跨 buffer 时也不会乱码 —— 两者等价，
    // 这里显式写出是为了强调字符集问题。
    final Stream<String> lines = response.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    // 静默超时的含义：整整 silenceTimeout 内一个字节都没收到。
    // 只要服务端还在发数据（心跳也算），这个计时就会被重置，
    // 所以它抓的是"连接已死"，不会误杀慢回答。
    try {
      await for (final String rawLine in lines.timeout(silenceTimeout)) {
        final String line = rawLine.trim();
        if (line.isEmpty) continue;

        // SSE 里还有 "event:" / "id:" / ":keep-alive" 等行，只要 data:
        if (!line.startsWith('data:')) continue;
        final String payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') {
          yield const ChatChunk('', done: true);
          break;
        }

        Map<String, dynamic> json;
        try {
          final Object? decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) continue;
          json = decoded;
        } catch (_) {
          // 半包/心跳等异常片段，跳过即可，不要中断整个回答
          continue;
        }

        // 有些兼容代理把错误塞在流里
        final Object? error = json['error'];
        if (error is Map && error['message'] is String) {
          throw DeepSeekException(
            '服务端返回错误：${error['message']}',
            failureKind: MessageFailure.provider,
          );
        }

        if (settings.protocol != 'openai') {
          for (final (text, thinking, done) in ApiProtocol.decode(
            settings.protocol,
            json,
          )) {
            yield ChatChunk(text, thinking: thinking, done: done);
          }
          continue;
        }
        final Object? choices = json['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final Object? first = choices.first;
        if (first is! Map) continue;

        final Object? delta = first['delta'];
        if (delta is Map) {
          final Object? reasoning = delta['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            yield ChatChunk(reasoning, thinking: true);
          }
          final Object? content = delta['content'];
          if (content is String && content.isNotEmpty) {
            yield ChatChunk(content);
          }
        } else {
          // 少数代理会把 stream 响应降级成完整 message
          final Object? message = first['message'];
          if (message is Map && message['content'] is String) {
            final String text = message['content'] as String;
            if (text.isNotEmpty) yield ChatChunk(text);
          }
        }

        // 结束原因：单独发一帧，交给上层决定是否提示截断/中断。
        final Object? finish = first['finish_reason'];
        if (finish is String && finish.isNotEmpty) {
          yield ChatChunk('', finishReason: finish);
        }
      }
    } on TimeoutException {
      throw DeepSeekException(
        '等待 ${presetFor(settings.providerId).name} 响应超过 '
        '${silenceTimeout.inSeconds ~/ 60} 分钟，连接可能已断开。请重试。',
        failureKind: MessageFailure.timeout,
      );
    }
  }

  // ------------------------------------------------------------- 非流式请求

  /// 备用方案：一次性拿完整答案。
  @override
  Future<String> completeChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async {
    if (settings.model.trim().isEmpty || settings.baseUrl.trim().isEmpty) {
      throw DeepSeekException('请先填写模型名称和 API 接口地址。');
    }
    cancel();
    final abort = Completer<void>();
    _abort = abort;
    final String apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      throw DeepSeekException('还没有填写 API Key，请先到「设置」里填写。');
    }

    final List<Map<String, dynamic>> apiMessages = await buildApiMessages(
      history,
      systemPrompt: settings.systemPrompt,
      imageDetail: settings.imageDetail,
    );

    if (!settings.supportsImages &&
        history.any((m) => !m.error && m.attachments.any((a) => a.isImage))) {
      throw DeepSeekException('当前模型未启用图片支持，请更换模型或在设置中确认图片能力。');
    }
    final request =
        http.AbortableRequest(
            'POST',
            ApiProtocol.endpoint(settings),
            abortTrigger: abort.future,
          )
          ..headers.addAll(ApiProtocol.headers(settings))
          ..body = jsonEncode(ApiProtocol.body(settings, apiMessages, false));
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(connectTimeout),
    ).timeout(silenceTimeout);

    final String raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode != 200) {
      throw DeepSeekException(
        _friendlyError(response.statusCode, raw),
        statusCode: response.statusCode,
      );
    }

    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      if (settings.protocol != 'openai') {
        return ApiProtocol.decode(
          settings.protocol,
          json,
          full: true,
        ).where((part) => !part.$2).map((part) => part.$1).join();
      }
      final List<dynamic> choices = json['choices'] as List<dynamic>;
      final Map<String, dynamic> message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      return (message['content'] as String?) ?? '';
    } catch (e) {
      throw DeepSeekException('无法解析服务端返回：${e.toString()}');
    }
  }

  // ------------------------------------------------------------------ 工具

  /// 把 HTTP 状态码 + 响应体翻译成用户能看懂的中文提示。
  String _friendlyError(int statusCode, String rawBody) {
    String detail = '';
    try {
      final Object? decoded = jsonDecode(rawBody);
      if (decoded is Map && decoded['error'] is Map) {
        final Object? msg = (decoded['error'] as Map)['message'];
        if (msg is String) detail = msg;
      }
    } catch (_) {
      detail = rawBody.length > 200 ? rawBody.substring(0, 200) : rawBody;
    }

    final String prefix = switch (statusCode) {
      400 => '请求格式有误（400）',
      401 => 'API Key 无效或已过期（401）',
      402 => '账户余额不足（402）',
      403 => '没有权限访问该模型（403）',
      404 => '接口地址不存在（404），请检查 Base URL',
      422 => '请求参数不合法（422）',
      429 => '请求过于频繁或被限流（429），稍后再试',
      500 || 502 || 503 || 504 => '模型服务暂时不可用（$statusCode），请稍后重试',
      _ => '请求失败（$statusCode）',
    };
    return detail.isEmpty ? prefix : '$prefix：$detail';
  }

  /// 连通性自检：设置页的「测试连接」按钮用。
  @override
  Future<String> testConnection(AppSettings settings) async {
    final ChatMessage probe = ChatMessage.user('你好');
    final String reply = await completeChat(
      settings: settings,
      history: <ChatMessage>[probe],
    );
    if (reply.trim().isEmpty) {
      throw DeepSeekException('服务端没有返回有效回答，请检查模型与接口配置。');
    }
    return reply;
  }
}
