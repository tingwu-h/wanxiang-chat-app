import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/pages/search_settings_page.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/widgets/chat_input_bar.dart';

/// v1.4.4：思考强度悬浮框、设置图标、联网设置页收尾。
void main() {
  Widget barHost({
    int level = 2,
    bool enabled = true,
    ValueChanged<int>? onPick,
    Size? size,
  }) {
    Widget app = MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(
            onSend: (String _) async => true,
            onStop: () {},
            onPickImages: () {},
            onPickFiles: () {},
            onTakePhoto: () {},
            onRemoveAttachment: (_) {},
            isLoading: false,
            enabled: true,
            thinkingAvailable: true,
            thinkingEnabled: enabled,
            thinkingLevel: level,
            thinkingEffort: enabled ? 'High' : 'No',
            onPickThinkingLevel: onPick ?? (_) {},
          ),
        ),
      ),
    );
    if (size != null) {
      app = SizedBox(width: size.width, height: size.height, child: app);
    }
    return app;
  }

  Finder popover() => find.byKey(const ValueKey('thinking-level-popover'));
  Finder chip() => find.byKey(const ValueKey('mode-chip-thinking'));

  group('思考强度悬浮框', () {
    testWidgets('点胶囊出现四个胶囊，没有完成按钮', (WidgetTester tester) async {
      await tester.pumpWidget(barHost());
      expect(popover(), findsNothing);

      await tester.tap(chip());
      await tester.pumpAndSettle();

      expect(popover(), findsOneWidget);
      for (final String label in <String>['No', 'Low', 'High', 'Max']) {
        expect(
          find.descendant(of: popover(), matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: popover(), matching: find.text('Done')),
        findsNothing,
      );
      expect(
        find.descendant(of: popover(), matching: find.text('完成')),
        findsNothing,
      );
    });

    testWidgets('选 Max 立即生效并收起', (WidgetTester tester) async {
      final List<int> picked = <int>[];
      await tester.pumpWidget(barHost(onPick: picked.add));

      await tester.tap(chip());
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: popover(), matching: find.text('Max')),
      );
      await tester.pumpAndSettle();

      expect(picked, <int>[3]);
      expect(popover(), findsNothing);
    });

    testWidgets('点框外收起且不改值', (WidgetTester tester) async {
      final List<int> picked = <int>[];
      await tester.pumpWidget(
        barHost(onPick: picked.add, size: const Size(400, 700)),
      );

      await tester.tap(chip());
      await tester.pumpAndSettle();
      expect(popover(), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(popover(), findsNothing);
      expect(picked, isEmpty);
    });

    testWidgets('悬浮框在胶囊上方', (WidgetTester tester) async {
      await tester.pumpWidget(barHost());

      await tester.tap(chip());
      await tester.pumpAndSettle();

      final Rect card = tester.getRect(popover());
      final Rect target = tester.getRect(chip());
      expect(card.bottom, lessThanOrEqualTo(target.top));
      expect(card.right, closeTo(target.right, 1));
    });

    testWidgets('320dp 宽不溢出', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(960, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(barHost());
      await tester.tap(chip());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(popover(), findsOneWidget);
    });

    testWidgets('再点胶囊收起，第三次重新打开', (WidgetTester tester) async {
      await tester.pumpWidget(barHost());

      await tester.tap(chip());
      await tester.pumpAndSettle();
      expect(popover(), findsOneWidget);

      // 浮层打开时遮罩在最上层，第二次点击落在遮罩上 = 收起。
      await tester.tap(chip(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(popover(), findsNothing);

      await tester.tap(chip());
      await tester.pumpAndSettle();
      expect(popover(), findsOneWidget);
    });
  });

  group('设置页入口', () {
    Future<void> mount(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      String? key;
      final StorageService storage = StorageService(
        readKey: () async => key,
        writeKey: (String v) async => key = v,
      );
      final AppSettingsProvider settings = AppSettingsProvider(
        storage: storage,
      );
      final ChatProvider chat = ChatProvider(
        api: DeepSeekService(),
        storage: storage,
      );
      await settings.init();
      await chat.init();
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(Scaffold).first)).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      );
      await tester.pumpAndSettle();
    }

    Future<void> expandSearch(WidgetTester tester) async {
      final Finder header = find.byKey(const ValueKey('section-search'));
      await tester.scrollUntilVisible(
        header,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
    }

    testWidgets('分组用滑杆图标，联网搜索设置用地球图标', (WidgetTester tester) async {
      await mount(tester);
      await expandSearch(tester);

      final Finder section = find.byKey(const ValueKey('section-search'));
      // 展开后的条目是 header 的兄弟节点，用 Card 作为范围才能一起覆盖。
      final Finder card = find
          .ancestor(of: section, matching: find.byType(Card))
          .first;
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.tune)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.travel_explore)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byIcon(Icons.psychology_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('联网搜索设置页不再出现迁移提示', (WidgetTester tester) async {
      await mount(tester);
      await expandSearch(tester);

      await tester.tap(find.text('联网搜索设置'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchSettingsPage), findsOneWidget);
      expect(find.textContaining('已移到'), findsNothing);
      expect(find.textContaining('模型行为」页面'), findsNothing);
    });
  });
}
