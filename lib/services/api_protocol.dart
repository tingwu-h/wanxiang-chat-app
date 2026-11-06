import 'package:deepseek_chat/models/app_settings.dart';

/// Pure wire adapters: shared by mobile and future desktop clients.
class ApiProtocol {
  static Uri endpoint(AppSettings s, {bool stream = false}) {
    var base = s.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.contains('://')) base = 'https://$base';
    base = base.replaceFirst(
      RegExp(r'/(chat/completions|responses|messages)$'),
      '',
    );
    final path = switch (s.protocol) {
      'responses' => '/responses',
      'anthropic' => '/messages',
      'gemini' =>
        '/models/${Uri.encodeComponent(s.model)}:${stream ? 'streamGenerateContent?alt=sse' : 'generateContent'}',
      _ => '/chat/completions',
    };
    final uri = Uri.parse('$base$path');
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (s.protocol != 'gemini' && uri.hasQuery)) {
      throw const FormatException('请输入有效的 HTTPS 接口地址');
    }
    return uri;
  }

  static Map<String, String> headers(AppSettings s) => {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'text/event-stream, application/json',
    if (s.protocol == 'anthropic') ...{
      'x-api-key': s.apiKey.trim(),
      'anthropic-version': '2023-06-01',
    } else if (s.protocol == 'gemini')
      'x-goog-api-key': s.apiKey.trim()
    else
      'Authorization': 'Bearer ${s.apiKey.trim()}',
  };

  static List<Map<String, dynamic>> blocks(dynamic content) => content is String
      ? [
          {'type': 'text', 'text': content},
        ]
      : List<Map<String, dynamic>>.from(content as List);

  static Map<String, String> imageData(Map<String, dynamic> b) {
    final url = (b['image_url'] as Map)['url'] as String;
    final match = RegExp(
      r'^data:([^;]+);base64,(.*)$',
      dotAll: true,
    ).firstMatch(url);
    if (match == null) throw const FormatException('仅支持本地图片附件');
    return {'mime': match.group(1)!, 'data': match.group(2)!};
  }

  static Map<String, dynamic> body(
    AppSettings s,
    List<Map<String, dynamic>> messages,
    bool stream,
  ) {
    final system = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'])
        .join('\n');
    final turns = messages.where((m) => m['role'] != 'system').toList();
    switch (s.protocol) {
      case 'anthropic':
        return {
          'model': s.model,
          // 4096 会把长回答截断（官方最大输出 384K）；8192 兼容性较好。
          'max_tokens': 8192,
          'stream': stream,
          if (system.isNotEmpty) 'system': system,
          'messages': turns
              .map(
                (m) => {
                  'role': m['role'],
                  'content': blocks(m['content']).map((b) {
                    if (b['type'] != 'image_url') return b;
                    final i = imageData(b);
                    return {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': i['mime'],
                        'data': i['data'],
                      },
                    };
                  }).toList(),
                },
              )
              .toList(),
        };
      case 'gemini':
        return {
          if (system.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': system},
              ],
            },
          'contents': turns
              .map(
                (m) => {
                  'role': m['role'] == 'assistant' ? 'model' : 'user',
                  'parts': blocks(m['content']).map((b) {
                    if (b['type'] != 'image_url') {
                      return <String, dynamic>{'text': b['text']};
                    }
                    final i = imageData(b);
                    return <String, dynamic>{
                      'inlineData': {'mimeType': i['mime'], 'data': i['data']},
                    };
                  }).toList(),
                },
              )
              .toList(),
          'generationConfig': {'temperature': s.temperature},
        };
      case 'responses':
        return {
          'model': s.model,
          'stream': stream,
          'store': false,
          if (system.isNotEmpty) 'instructions': system,
          'input': turns
              .map(
                (m) => {
                  'role': m['role'],
                  'content': blocks(m['content'])
                      .map(
                        (b) => b['type'] == 'image_url'
                            ? {
                                'type': 'input_image',
                                'image_url': (b['image_url'] as Map)['url'],
                              }
                            : {
                                'type': m['role'] == 'assistant'
                                    ? 'output_text'
                                    : 'input_text',
                                'text': b['text'],
                              },
                      )
                      .toList(),
                },
              )
              .toList(),
        };
      default:
        return {
          'model': s.model,
          'messages': messages,
          'stream': stream,
          // DeepSeek 思考模式：官方用 thinking.type 开关，reasoning_effort 控强度。
          // 官方默认开启思考模式，所以缺省状态与官方一致。
          if (s.providerId == 'deepseek') ...<String, dynamic>{
            'thinking': <String, dynamic>{
              'type': s.thinkingEnabled ? 'enabled' : 'disabled',
            },
            'reasoning_effort': s.reasoningEffort,
          },
          // 官方明确：思考模式下 temperature 不生效（不报错但无效果）。
          // 因此只在思考模式关闭时才发送，避免出现「拖了滑块却没反应」的假开关。
          if (!<String>['openai', 'kimi', 'glm', 'xai'].contains(s.providerId) &&
              !s.isThinkingActive)
            'temperature': s.temperature,
        };
    }
  }

  /// (text, isThinking, isDone). No provider transport types leak into UI.
  static Iterable<(String, bool, bool)> decode(
    String protocol,
    Map<String, dynamic> json, {
    bool full = false,
  }) sync* {
    if (json['error'] case final Map error) {
      throw FormatException('服务端返回错误：${error['message'] ?? error['status']}');
    }
    if (protocol == 'anthropic') {
      if (full) {
        for (final b in json['content'] as List? ?? []) {
          if (b['type'] == 'text') yield (b['text'] as String, false, false);
          if (b['type'] == 'thinking') {
            yield (b['thinking'] as String, true, false);
          }
        }
      } else {
        final delta = json['delta'];
        if (delta is Map) {
          if (delta['text'] is String) {
            yield (delta['text'] as String, false, false);
          }
          if (delta['thinking'] is String) {
            yield (delta['thinking'] as String, true, false);
          }
        }
        if (json['type'] == 'message_stop') yield ('', false, true);
      }
    } else if (protocol == 'gemini') {
      if (json['promptFeedback'] case final Map feedback) {
        if (feedback['blockReason'] != null) {
          throw FormatException('请求被服务商拦截：${feedback['blockReason']}');
        }
      }
      final candidates = json['candidates'] as List? ?? [];
      if (candidates.isNotEmpty) {
        final candidate = candidates.first as Map;
        for (final part
            in (candidate['content'] as Map?)?['parts'] as List? ?? []) {
          if (part['text'] is String) {
            yield (part['text'] as String, part['thought'] == true, false);
          }
        }
        if (candidate['finishReason'] != null) yield ('', false, true);
      }
    } else if (protocol == 'responses') {
      if (full) {
        for (final item in json['output'] as List? ?? []) {
          for (final b in item['content'] as List? ?? []) {
            if (b['type'] == 'output_text') {
              yield (b['text'] as String, false, false);
            }
          }
        }
      } else {
        final type = json['type'];
        if (type == 'response.output_text.delta') {
          yield (json['delta'] as String, false, false);
        }
        if (type == 'response.reasoning_summary_text.delta') {
          yield (json['delta'] as String, true, false);
        }
        if (type == 'response.failed' || type == 'response.incomplete') {
          throw FormatException(
            '模型响应未完成：${(json['response'] as Map?)?['error'] ?? type}',
          );
        }
        if (type == 'response.completed') yield ('', false, true);
      }
    }
  }
}
