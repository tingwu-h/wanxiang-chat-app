import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/widgets/message_bubble.dart';

/// v1.3.4 回归：区分「正常回答 / 超时 / 服务商·网络失败」三类。
///
/// 背景：DeepSeek 服务异常时出现过「一直转圈停不下来」。
/// 修复的关键约束是**不能误杀慢回答**——本文件里最重要的那条测试
/// 就是验证慢但持续产出的回答能完整跑完。

/// 可以按脚本产出事件的假服务
class ScriptedApi extends DeepSeekService {
  ScriptedApi(this.script);

  /// 每项之间的等待时长；事件按顺序发出，最后自动结束
  final List<(Duration, ChatChunk)> script;

  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    for (final (Duration delay, ChatChunk chunk) in script) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      yield chunk;
    }
  }
}

/// 直接抛指定异常的假服务
class ThrowingApi extends DeepSeekService {
  ThrowingApi(this.error);
  final Object error;

  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    throw error;
  }
}

/// 永不结束、也不产出内容的假服务（模拟服务端连上后毫无响应）
class HangingApi extends DeepSeekService {
  final Completer<void> _never = Completer<void>();

  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    yield* Stream<ChatChunk>.fromFuture(_never.future.then((_) => const ChatChunk('')));
  }
}

Future<void> tick([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<ChatProvider> ready(ChatService api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final ChatProvider p = ChatProvider(api: api, storage: StorageService());
  await p.init();
  return p;
}

void main() {
  group('失败分类器', () {
    test('超时归为 timeout', () {
      expect(
        classifyFailure(TimeoutException('slow')),
        MessageFailure.timeout,
      );
      expect(
        classifyFailure(
          DeepSeekException('x', failureKind: MessageFailure.timeout),
        ),
        MessageFailure.timeout,
      );
    });

    test('网络异常归为 network（含被 http 包起来的 SocketException）', () {
      expect(
        classifyFailure(const SocketException('connection reset')),
        MessageFailure.network,
      );
      // http 会把底层 socket 错误包成 ClientException，分类器要看 cause
      expect(
        classifyFailure(
          http.ClientException('Connection closed', null),
        ),
        MessageFailure.network,
      );
    });

    test('服务商错误归为 provider（默认兜底）', () {
      expect(
        classifyFailure(DeepSeekException('服务端 503')),
        MessageFailure.provider,
      );
      expect(
        classifyFailure(StateError('unexpected')),
        MessageFailure.provider,
      );
    });
  });

  group('最关键的约束：慢回答不能被误杀', () {
    test('产出很慢但持续的流能完整跑完，不被中断', () async {
      // 每 40ms 才来一个字，全程约 600ms；真正的静默超时是 180 秒，
      // 只要判据是「零字节才算静默」，这种慢流永远不会被碰。
      final List<(Duration, ChatChunk)> slow = <(Duration, ChatChunk)>[
        for (int i = 0; i < 15; i++)
          (const Duration(milliseconds: 40), ChatChunk('字$i')),
        (const Duration(milliseconds: 40), const ChatChunk('', done: true)),
      ];
      final ChatProvider p = await ready(ScriptedApi(slow));
      await p.send('问题', AppSettings(apiKey: 'k'));

      expect(p.isLoading, isFalse, reason: '流结束后必须停止转圈');
      final ChatMessage last = p.messages.last;
      expect(last.error, isFalse, reason: '慢回答不能被当成失败');
      expect(last.failureKind, isNull);
      for (int i = 0; i < 15; i++) {
        expect(last.content.contains('字$i'), isTrue, reason: '第 $i 段不能丢');
      }
    });

    test('先安静一会再出内容，也不算超时', () async {
      // 首字前静默 400ms（远超「没内容就杀」的常见阈值），仍应成功
      final ChatProvider p = await ready(
        ScriptedApi(<(Duration, ChatChunk)>[
          (const Duration(milliseconds: 400), const ChatChunk('迟到的回答')),
          (Duration.zero, const ChatChunk('', done: true)),
        ]),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      expect(p.messages.last.error, isFalse);
      expect(p.messages.last.content, '迟到的回答');
      expect(p.isLoading, isFalse);
    });

    test('静默超时阈值足够宽松（不小于 3 分钟）', () {
      expect(
        DeepSeekService.silenceTimeout.inSeconds,
        greaterThanOrEqualTo(180),
        reason: '阈值太小会误杀慢回答',
      );
    });
  });

  group('三类失败的提示与标记', () {
    test('超时：标 timeout，文案友好且不含技术词', () async {
      final ChatProvider p = await ready(
        ThrowingApi(TimeoutException('Future not completed')),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      final ChatMessage last = p.messages.last;
      expect(last.error, isTrue);
      expect(last.failureKind, MessageFailure.timeout);
      expect(last.content.contains('超时'), isTrue);
      expect(
        last.content.contains('TimeoutException'),
        isFalse,
        reason: '不能把技术异常名丢给用户看',
      );
      expect(p.isLoading, isFalse, reason: '失败后必须停止转圈');
    });

    test('网络错误：标 network', () async {
      final ChatProvider p = await ready(
        ThrowingApi(const SocketException('reset by peer')),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      final ChatMessage last = p.messages.last;
      expect(last.failureKind, MessageFailure.network);
      expect(last.content.contains('网络'), isTrue);
      expect(last.content.contains('SocketException'), isFalse);
      expect(p.isLoading, isFalse);
    });

    test('服务商错误：标 provider，保留服务端给出的信息', () async {
      final ChatProvider p = await ready(
        ThrowingApi(
          DeepSeekException('模型服务暂时不可用（503）', statusCode: 503),
        ),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      final ChatMessage last = p.messages.last;
      expect(last.failureKind, MessageFailure.provider);
      expect(last.content.contains('503'), isTrue);
      expect(p.isLoading, isFalse);
    });

    test('已收到部分内容后中断：保留内容并追加中断提示', () async {
      final ChatProvider p = await ready(
        _PartialThenFailApi(<ChatChunk>[
          const ChatChunk('前半段'),
          const ChatChunk('后半段'),
        ]),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      final ChatMessage last = p.messages.last;
      expect(last.content.startsWith('前半段后半段'), isTrue,
          reason: '已收到的内容不能丢');
      expect(last.content.contains('连接中断'), isTrue);
      expect(last.failureKind, MessageFailure.network);
      expect(p.isLoading, isFalse);
    });

    test('流正常结束但没有任何内容：算服务商没给回答', () async {
      final ChatProvider p = await ready(
        ScriptedApi(<(Duration, ChatChunk)>[
          (Duration.zero, const ChatChunk('', done: true)),
        ]),
      );
      await p.send('问题', AppSettings(apiKey: 'k'));

      final ChatMessage last = p.messages.last;
      expect(last.error, isTrue);
      expect(last.failureKind, MessageFailure.provider);
      expect(p.isLoading, isFalse);
    });
  });

  group('转圈一定有尽头（不会永远加载）', () {
    test('服务端连上后毫无响应时，finally 仍会执行、转圈会停', () async {
      // 真实场景里服务层会在 silenceTimeout 后抛错；
      // 这里用一个永不结束的流模拟「服务层也卡住」的极端情况，
      // 验证 Provider 自己的兜底超时能把状态收回来。
      final ChatProvider p = await ready(HangingApi());
      unawaited(p.send('问题', AppSettings(apiKey: 'k')));
      await tick(120);
      expect(
        p.isLoading,
        isTrue,
        reason: '刚发出请求时本来就应该在加载',
      );
      // 兜底超时是 300 秒，测试里不能真等；只断言机制存在：
      // 停止按钮随时可用，用户不会被永久困住。
      p.stop();
      await tick();
      expect(p.isLoading, isFalse, reason: 'stop 必须立刻结束加载状态');
    });
  });

  group('聊天消息的失败标记可持久化', () {
    test('JSON 往返保留 failureKind', () {
      final ChatMessage m = ChatMessage(
        role: MessageRole.assistant,
        content: '出错了',
        error: true,
        failureKind: MessageFailure.network,
      );
      final ChatMessage back = ChatMessage.fromJson(m.toJson());
      expect(back.error, isTrue);
      expect(back.failureKind, MessageFailure.network);
    });

    test('旧数据没有 failureKind 时读成 null，不报错', () {
      final ChatMessage back = ChatMessage.fromJson(<String, dynamic>{
        'role': MessageRole.assistant,
        'content': '旧的错误气泡',
        'error': true,
      });
      expect(back.error, isTrue);
      expect(back.failureKind, isNull);
      expect(back.hasFailureKind, isFalse);
    });

    test('未知的 failureKind 值被忽略', () {
      final ChatMessage back = ChatMessage.fromJson(<String, dynamic>{
        'role': MessageRole.assistant,
        'content': 'x',
        'error': true,
        'failureKind': 'something-else',
      });
      expect(back.failureKind, isNull);
    });
  });

  group('错误气泡按类别显示图标', () {
    Future<void> pumpBubble(WidgetTester tester, String? kind) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                role: MessageRole.assistant,
                content: '出错了',
                error: true,
                failureKind: kind,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('超时显示沙漏图标', (WidgetTester tester) async {
      await pumpBubble(tester, MessageFailure.timeout);
      expect(find.byIcon(Icons.hourglass_disabled_outlined), findsOneWidget);
    });

    testWidgets('网络错误显示断网图标', (WidgetTester tester) async {
      await pumpBubble(tester, MessageFailure.network);
      expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
    });

    testWidgets('服务商错误显示云端故障图标', (WidgetTester tester) async {
      await pumpBubble(tester, MessageFailure.provider);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('没有类别信息时只渲染文字，不显示图标', (WidgetTester tester) async {
      await pumpBubble(tester, null);
      expect(find.text('出错了'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_disabled_outlined), findsNothing);
      expect(find.byIcon(Icons.wifi_off_outlined), findsNothing);
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });
  });
}

/// 先产出若干内容，然后以网络错误中断
class _PartialThenFailApi extends DeepSeekService {
  _PartialThenFailApi(this.chunks);
  final List<ChatChunk> chunks;

  @override
  Stream<ChatChunk> streamChat({
    required AppSettings settings,
    required List<ChatMessage> history,
  }) async* {
    for (final ChatChunk c in chunks) {
      yield c;
    }
    throw const SocketException('connection reset');
  }
}
