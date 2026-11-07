import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/services/api_protocol.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';
import 'package:deepseek_chat/widgets/thinking_level_sheet.dart';
import 'package:deepseek_chat/widgets/thinking_level_slider.dart';

void main() {
  group('四档映射', () {
    test('thinkingLevel 覆盖四个档位', () {
      expect(
        AppSettings(thinkingEnabled: false, reasoningEffort: 'max').thinkingLevel,
        0,
      );
      expect(
        AppSettings(thinkingEnabled: true, reasoningEffort: 'low').thinkingLevel,
        1,
      );
      expect(
        AppSettings(thinkingEnabled: true, reasoningEffort: 'high').thinkingLevel,
        2,
      );
      expect(
        AppSettings(thinkingEnabled: true, reasoningEffort: 'max').thinkingLevel,
        3,
      );
    });

    test('effortForLevel：0 档返回 null，不覆盖上次强度', () {
      expect(AppSettings.effortForLevel(0), isNull);
      expect(AppSettings.effortForLevel(1), 'low');
      expect(AppSettings.effortForLevel(2), 'high');
      expect(AppSettings.effortForLevel(3), 'max');
    });

    test('滑到 No 再滑回来能恢复原档', () {
      final AppSettings on = AppSettings(
        thinkingEnabled: true,
        reasoningEffort: 'max',
      );
      final AppSettings off = on.copyWith(thinkingEnabled: false);
      expect(off.reasoningEffort, 'max');
      expect(off.thinkingLevel, 0);
      final AppSettings back = off.copyWith(thinkingEnabled: true);
      expect(back.thinkingLevel, 3);
    });

    test('老数据（只有 thinkingEnabled=false）落在 No 档', () {
      final AppSettings s = AppSettings.fromJson(<String, dynamic>{
        'thinkingEnabled': false,
      });
      expect(s.thinkingLevel, 0);
      expect(s.reasoningEffort, 'high');
    });

    test('缺省仍是开启 + High', () {
      final AppSettings s = AppSettings.fromJson(<String, dynamic>{});
      expect(s.thinkingLevel, 2);
      expect(s.thinkingLevelLabel, 'High');
    });
  });

  group('四档滑条', () {
    Widget host({
      int level = 2,
      ValueChanged<int>? onCommit,
      bool enabled = true,
    }) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      home: Scaffold(
        body: ThinkingLevelSlider(
          level: level,
          enabled: enabled,
          onCommit: onCommit ?? (_) {},
        ),
      ),
    );

    testWidgets('标签是 No / Low / High / Max，不出现“不思考”', (WidgetTester tester) async {
      await tester.pumpWidget(host());
      for (final String label in <String>['No', 'Low', 'High', 'Max']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('不思考'), findsNothing);
    });

    testWidgets('点 Max 回调 3，点 No 回调 0', (WidgetTester tester) async {
      final List<int> committed = <int>[];
      await tester.pumpWidget(host(onCommit: committed.add));

      await tester.tap(find.text('Max'));
      await tester.pumpAndSettle();
      expect(committed.last, 3);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(committed.last, 0);
    });

    testWidgets('拖动过程中不回调，松手只回调一次', (WidgetTester tester) async {
      final List<int> committed = <int>[];
      await tester.pumpWidget(host(onCommit: committed.add));

      await tester.dragFrom(
        tester.getCenter(find.byType(Slider)),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(committed.length, 1);
    });

    testWidgets('禁用时点标签无效', (WidgetTester tester) async {
      final List<int> committed = <int>[];
      await tester.pumpWidget(
        host(enabled: false, onCommit: committed.add),
      );
      await tester.tap(find.text('Max'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(committed, isEmpty);
    });
  });

  group('输入栏思考胶囊', () {
    Widget bar({
      bool enabled = true,
      String effort = 'High',
      bool available = true,
    }) => MaterialApp(
      locale: const Locale('zh', 'CN'),
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
          thinkingEffort: effort,
          onOpenThinking: () {},
        ),
      ),
    );

    Color? chipColor(WidgetTester tester) {
      final Finder chip = find.byKey(const ValueKey('mode-chip-thinking'));
      final AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
      );
      return (container.decoration! as ShapeDecoration).color;
    }

    testWidgets('开启时显示「思考·High」并高亮', (WidgetTester tester) async {
      await tester.pumpWidget(bar());
      // 默认 locale 是 en_US，tr('思考') 会返回 Think；两种都算通过。
      expect(find.textContaining('·High'), findsOneWidget);
      expect(chipColor(tester), isNot(Colors.transparent));
    });

    testWidgets('No 档只显示「思考」，且取消高亮', (WidgetTester tester) async {
      await tester.pumpWidget(bar(enabled: false));
      final Finder chip = find.byKey(const ValueKey('mode-chip-thinking'));
      final String label = tester
          .widget<Text>(
            find.descendant(of: chip, matching: find.byType(Text)).first,
          )
          .data!;
      expect(label, anyOf('思考', 'Think'));
      expect(find.textContaining('·'), findsNothing);
      expect(chipColor(tester), Colors.transparent);
    });

    testWidgets('非 DeepSeek 不显示思考胶囊', (WidgetTester tester) async {
      await tester.pumpWidget(bar(available: false));
      expect(find.byKey(const ValueKey('mode-chip-thinking')), findsNothing);
    });

    testWidgets('320dp 小屏 + 长档位标签不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(960, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
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
              thinkingAvailable: true,
              thinkingEnabled: true,
              thinkingEffort: 'High',
              onOpenThinking: () {},
              searchEnabled: true,
              searchAvailable: true,
              onToggleSearch: () {},
              modelSelector: const Text('deepseek-flash'),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('底部面板', () {
    testWidgets('显示标题、完成按钮与四档，点 Max 生效', (WidgetTester tester) async {
      final List<int> committed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: Scaffold(
            body: ThinkingLevelSheet(level: 0, onCommit: committed.add),
          ),
        ),
      );
      // 测试环境默认 en_US，标题按语言可能取中文或英文。
      expect(
        find.text('思考强度').evaluate().isNotEmpty ||
            find.text('Thinking level').evaluate().isNotEmpty,
        isTrue,
      );
      expect(
        find.text('完成').evaluate().isNotEmpty ||
            find.text('Done').evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);

      await tester.tap(find.text('Max'));
      await tester.pumpAndSettle();
      expect(committed.last, 3);
    });
  });

  group('请求体', () {
    test('No 档：thinking.type=disabled 且发送 temperature', () {
      final AppSettings s = AppSettings(
        model: 'deepseek-flash',
        thinkingEnabled: false,
        temperature: 0.8,
      );
      final Map<String, dynamic> body = ApiProtocol.body(
        s,
        <Map<String, dynamic>>[],
        true,
      );
      expect((body['thinking'] as Map)['type'], 'disabled');
      expect(body['temperature'], 0.8);
    });

    test('Low / High / Max：enabled + 对应强度，且不含 temperature', () {
      for (final (int level, String effort) in <(int, String)>[
        (1, 'low'),
        (2, 'high'),
        (3, 'max'),
      ]) {
        final AppSettings s = AppSettings(
          model: 'deepseek-flash',
          thinkingEnabled: true,
          reasoningEffort: effort,
          temperature: 0.8,
        );
        final Map<String, dynamic> body = ApiProtocol.body(
          s,
          <Map<String, dynamic>>[],
          true,
        );
        expect((body['thinking'] as Map)['type'], 'enabled');
        expect(body['reasoning_effort'], effort, reason: 'level $level');
        expect(body.containsKey('temperature'), isFalse);
      }
    });
  });
}
