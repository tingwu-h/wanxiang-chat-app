import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/chat_source.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/search_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';

/// v1.4.1：时间注入、深度思考快捷开关、联网图标。

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

class NoopSearch extends SearchService {
  @override
  Future<SearchOutcome> search({
    required String apiKey,
    required String query,
    String? oriQuestion,
    int count = AppSettings.defaultSearchCount,
    bool fetchContent = false,
  }) async => const SearchOutcome(sources: <ChatSource>[], contextText: '');

  @override
  void dispose() {}
}

Future<(ChatProvider, CapturingApi)> ready() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final CapturingApi api = CapturingApi();
  final ChatProvider p = ChatProvider(
    api: api,
    storage: StorageService(),
    search: NoopSearch(),
  );
  await p.init();
  return (p, api);
}

void main() {
  group('时间注入（修复「无法确定今天几号」）', () {
    test('默认开启：请求的系统提示词里带当前时间', () async {
      final (ChatProvider p, CapturingApi api) = await ready();
      await p.send('今天几号', AppSettings(apiKey: 'k'));

      final String sys = api.captured?.systemPrompt ?? '';
      expect(sys, contains('当前时间'), reason: '不注入模型只能回答无法确定');
      expect(sys, contains('星期'));
      // 年份应与设备一致（不写死具体日期，避免测试在跨年后失效）
      expect(sys, contains('${DateTime.now().year}-'));
    });

    test('关闭后不再注入日期', () async {
      final (ChatProvider p, CapturingApi api) = await ready();
      await p.send(
        '今天几号',
        AppSettings(apiKey: 'k', injectCurrentTime: false),
      );
      final String sys = api.captured?.systemPrompt ?? '';
      expect(sys.contains('当前时间'), isFalse);
    });

    test('注入不覆盖每会话提示词，两者共存', () async {
      final (ChatProvider p, CapturingApi api) = await ready();
      await p.setActiveSystemPrompt('你是猫娘');
      await p.send('你叫什么', AppSettings(apiKey: 'k'));

      final String sys = api.captured?.systemPrompt ?? '';
      expect(sys, contains('当前时间'));
      expect(sys, contains('你是猫娘'));
    });

    test('联网关闭时提示不要含糊其辞', () async {
      final (ChatProvider p, CapturingApi api) = await ready();
      await p.send('最新新闻', AppSettings(apiKey: 'k', searchEnabled: false));
      final String sys = api.captured?.systemPrompt ?? '';
      expect(sys, contains('实时检索'));
    });

    test('设置可持久化', () {
      final AppSettings s = AppSettings(injectCurrentTime: false);
      expect(AppSettings.fromJson(s.toJson()).injectCurrentTime, isFalse);
      // 旧数据缺字段时默认开启
      expect(AppSettings.fromJson(<String, dynamic>{}).injectCurrentTime, isTrue);
    });
  });

  group('深度思考快捷开关', () {
    Widget bar({required bool available, required bool enabled}) =>
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              onSend: (String _) async => true,
              onStop: () {},
              onPickImages: () {},
              onPickFiles: () {},
              onTakePhoto: () {},
              onRemoveAttachment: (_) {},
              isLoading: false,
              enabled: true,
              thinkingAvailable: available,
              thinkingEnabled: enabled,
              onPickThinkingLevel: (_) {},
            ),
          ),
        );

    testWidgets('DeepSeek 下显示深度思考按钮', (WidgetTester tester) async {
      await tester.pumpWidget(bar(available: true, enabled: true));
      expect(find.byIcon(Icons.psychology), findsOneWidget);
    });

    testWidgets('开启与关闭的图标不同（状态可见）', (WidgetTester tester) async {
      await tester.pumpWidget(bar(available: true, enabled: true));
      expect(find.byIcon(Icons.psychology), findsOneWidget);

      await tester.pumpWidget(bar(available: true, enabled: false));
      expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
    });

    testWidgets('非 DeepSeek 不显示该按钮', (WidgetTester tester) async {
      await tester.pumpWidget(bar(available: false, enabled: true));
      expect(find.byIcon(Icons.psychology), findsNothing);
      expect(find.byIcon(Icons.psychology_outlined), findsNothing);
    });
  });

  group('联网开关：图标与位置', () {
    Widget bar({
      bool searchAvailable = true,
      bool searchEnabled = false,
      bool thinkingAvailable = false,
      Widget? modelSelector,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: ChatInputBar(
              onSend: (String _) async => true,
              onStop: () {},
              onPickImages: () {},
              onPickFiles: () {},
              onTakePhoto: () {},
              onRemoveAttachment: (_) {},
              isLoading: false,
              enabled: true,
              searchAvailable: searchAvailable,
              searchEnabled: searchEnabled,
              onToggleSearch: () {},
              thinkingAvailable: thinkingAvailable,
              thinkingEnabled: true,
              onPickThinkingLevel: (_) {},
              modelSelector: modelSelector,
            ),
          ),
        );

    testWidgets('用矢量图标，不再依赖位图资源', (WidgetTester tester) async {
      await tester.pumpWidget(bar());
      final bool usesBitmap = tester
          .widgetList<Image>(find.byType(Image))
          .any((Image img) => img.image is AssetImage);
      expect(usesBitmap, isFalse, reason: '不能用位图图标（18dp 会发虚）');
      // 关闭态用描边地球
      expect(find.byIcon(Icons.travel_explore_outlined), findsOneWidget);
    });

    /// 读取胶囊里的文字（不依赖语言：中英文都算通过）
    String chipLabel(WidgetTester tester, Key key) {
      final Finder finder = find.descendant(
        of: find.byKey(key),
        matching: find.byType(Text),
      );
      expect(finder, findsWidgets);
      return tester.widget<Text>(finder.first).data ?? '';
    }

    testWidgets('开启态换成实心地球，并显示文字', (WidgetTester tester) async {
      await tester.pumpWidget(bar(searchEnabled: true));
      expect(find.byIcon(Icons.travel_explore), findsOneWidget);
      expect(
        chipLabel(tester, const ValueKey('mode-chip-search')),
        anyOf('联网', 'Web'),
      );
    });

    testWidgets('两个开关都在底部行（模型选择器同一行）', (WidgetTester tester) async {
      await tester.pumpWidget(
        bar(thinkingAvailable: true, modelSelector: const Text('deepseek-flash')),
      );
      final Finder thinking = find.byKey(const ValueKey('mode-chip-thinking'));
      final Finder search = find.byKey(const ValueKey('mode-chip-search'));
      expect(thinking, findsOneWidget);
      expect(search, findsOneWidget);

      // 两者纵向位置应接近模型胶囊，而不是贴着输入框
      final double modelY = tester.getCenter(find.text('deepseek-flash')).dy;
      expect((tester.getCenter(thinking).dy - modelY).abs() < 24, isTrue);
      expect((tester.getCenter(search).dy - modelY).abs() < 24, isTrue);
    });

    testWidgets('两个胶囊都带文字标签', (WidgetTester tester) async {
      await tester.pumpWidget(bar(thinkingAvailable: true));
      expect(
        chipLabel(tester, const ValueKey('mode-chip-search')),
        anyOf('联网', 'Web'),
      );
      expect(
        chipLabel(tester, const ValueKey('mode-chip-thinking')),
        anyOf('思考', 'Think'),
      );
    });
  });
}
