import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_attachment.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/attachment_service.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

class Paths extends PathProviderPlatform {
  Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class WaitingClient extends http.BaseClient {
  final started = Completer<void>();
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    await (request as http.AbortableRequest).abortTrigger;
    aborted = true;
    throw http.RequestAbortedException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['DS_UI_CAPTURE'] != 'true') return;
    final font = Platform.environment['DS_UI_FONT'];
    if (font != null && await File(font).exists()) {
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(
              File(font).readAsBytes().then((b) => ByteData.sublistView(b)),
            ))
            .load();
      }
    }
    final icons = Platform.environment['DS_UI_ICON_FONT'];
    if (icons != null && await File(icons).exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            File(icons).readAsBytes().then((b) => ByteData.sublistView(b)),
          ))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy key migrates before plaintext is removed; failure keeps old key',
    () async {
      SharedPreferences.setMockInitialValues({
        'ds_settings': jsonEncode({
          'apiKey': 'fixture-key',
          'model': 'deepseek-flash',
        }),
      });
      String? secret;
      final storage = StorageService(
        readKey: () async => secret,
        writeKey: (key) async {
          secret = key;
        },
      );
      expect((await storage.loadSettings()).apiKey, 'fixture-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ds_settings'), isNot(contains('fixture-key')));
      expect((await storage.loadSettings()).apiKey, 'fixture-key');
      await storage.saveSettings(AppSettings(apiKey: ''));
      expect(secret, '');
      await prefs.setString(
        'ds_settings',
        jsonEncode({'apiKey': 'retain-on-failure'}),
      );
      final failing = StorageService(
        writeKey: (_) async => throw StateError('locked'),
      );
      await expectLater(failing.loadSettings(), throwsStateError);
      expect(prefs.getString('ds_settings'), contains('retain-on-failure'));
    },
  );

  test(
    'concurrent saves retain every conversation and do not trim messages',
    () async {
      final storage = StorageService();
      final large = Conversation(
        id: 'large',
        messages: List.generate(510, (i) => ChatMessage.user('message $i')),
      );
      await Future.wait([
        storage.saveConversation(large),
        ...List.generate(
          102,
          (i) => storage.saveConversation(Conversation(id: 'c$i')),
        ),
      ]);
      final all = await storage.loadConversations();
      expect(all.length, 103);
      expect(all.firstWhere((c) => c.id == 'large').messages.length, 510);
    },
  );

  test(
    'attachment cleanup preserves shared references and original files',
    () async {
      final root = await Directory.systemTemp.createTemp('deepseek-117-test-');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = Paths(root.path);
      try {
        final dir = await Directory('${root.path}/attachments').create();
        final image = await File('${dir.path}/shared.png')
            .writeAsBytes([1, 2, 3]);
        final original = await File('${root.path}/original.png')
            .writeAsBytes([4]);
        final attachment = ChatAttachment(
          name: 'shared.png',
          path: image.path,
          kind: 'image',
        );
        final storage = StorageService();
        await storage.saveConversation(
          Conversation(
            id: 'a',
            messages: [
              ChatMessage.user('A', attachments: [attachment]),
            ],
          ),
        );
        await storage.saveConversation(
          Conversation(
            id: 'b',
            messages: [
              ChatMessage.user('B', attachments: [attachment]),
            ],
          ),
        );
        await storage.deleteConversation('a');
        expect(await image.exists(), isTrue);
        await storage.deleteConversation('b');
        expect(await image.exists(), isFalse);
        await AttachmentService.removeOwnedFile(original.path);
        expect(await original.exists(), isTrue);
      } finally {
        PathProviderPlatform.instance = previous;
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'oversized and missing images fail explicitly; selection is bounded',
    () async {
      final dir = await Directory.systemTemp.createTemp('deepseek-117-limit-');
      try {
        final file = File('${dir.path}/large.png');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(AttachmentService.maxImageBytes + 1);
        await handle.close();
        final a = ChatAttachment(
          name: 'large.png',
          path: file.path,
          kind: 'image',
        );
        await expectLater(a.toApiBlock(), throwsA(isA<AttachmentException>()));
        await file.delete();
        await expectLater(a.toApiBlock(), throwsA(isA<AttachmentException>()));
        expect(
          () => AttachmentService.validateSelection(List.filled(7, a)),
          throwsA(isA<AttachmentException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('export excludes secrets and image paths', () async {
    final storage = StorageService();
    await storage.saveSettings(AppSettings(apiKey: 'do-not-export'));
    await storage.saveConversation(
      Conversation(
        id: 'export',
        messages: [
          ChatMessage.user(
            'hello',
            attachments: [
              ChatAttachment(
                name: 'photo.png',
                path: '/private/photo.png',
                kind: 'image',
              ),
            ],
          ),
        ],
      ),
    );
    final result = await storage.exportHistory();
    expect(result, contains('hello'));
    expect(result, isNot(contains('do-not-export')));
    expect(result, isNot(contains('/private/photo.png')));
  });

  test('cancels real HTTP request handle before headers arrive', () async {
    final client = WaitingClient();
    final api = DeepSeekService(client: client);
    final future = api
        .streamChat(
          settings: AppSettings(apiKey: 'fixture'),
          history: [ChatMessage.user('hi')],
        )
        .toList();
    final assertion = expectLater(
      future,
      throwsA(isA<http.RequestAbortedException>()),
    );
    await client.started.future;
    api.cancel();
    await assertion;
    expect(client.aborted, isTrue);
    api.dispose();
  });

  test('accepts JSON stream fallback without duplicating request', () async {
    int calls = 0;
    final api = DeepSeekService(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'reply', 'reasoning_content': 'think'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final chunks = await api
        .streamChat(
          settings: AppSettings(apiKey: 'fixture'),
          history: [ChatMessage.user('hi')],
        )
        .toList();
    expect(chunks.map((c) => c.text).toList(), ['think', 'reply']);
    expect(calls, 1);
    api.dispose();
  });

  test('rejects insecure endpoints and incompatible image history', () {
    expect(
      () => DeepSeekService.endpoint('http://example.com'),
      throwsA(isA<DeepSeekException>()),
    );
    expect(
      DeepSeekService.endpoint('https://example.com/v1/chat/completions').path,
      '/v1/chat/completions',
    );
    expect(
      () => DeepSeekService.validateImages('deepseek-v4-pro', [
        ChatMessage.user(
          'image',
          attachments: [
            ChatAttachment(name: 'a.png', path: 'a.png', kind: 'image'),
          ],
        ),
      ]),
      throwsA(isA<DeepSeekException>()),
    );
  });

  testWidgets(
    'back timeout and drawer do not exit; dark settings remain usable',
    (tester) async {
      final storage = StorageService();
      final settings = AppSettingsProvider(storage: storage);
      final chat = ChatProvider(api: DeepSeekService(), storage: storage);
      await settings.init();
      await chat.init();
      int exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        },
      );
      await tester.pumpWidget(
        DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 0);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      chat.dispose();
    },
  );

  testWidgets('mobile layouts: light chat, dark chat, settings and history', (
    tester,
  ) async {
    if (Platform.environment['DS_UI_CAPTURE'] == 'true') {
      await tester.runAsync(() async {
        final fontPath = Platform.environment['DS_PREVIEW_FONT'];
        final iconsPath = Platform.environment['DS_PREVIEW_ICONS'];
        if (fontPath != null) {
          final loader = FontLoader('Roboto')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(fontPath).readAsBytes()),
              ),
            );
          await loader.load();
        }
        if (iconsPath != null) {
          final loader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(await File(iconsPath).readAsBytes()),
              ),
            );
          await loader.load();
        }
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final storage = StorageService();
    final settings = AppSettingsProvider(storage: storage);
    final chat = ChatProvider(api: DeepSeekService(), storage: storage);
    await storage.saveConversation(
      Conversation(
        id: 'preview',
        messages: [
          ChatMessage.user('帮我把今天的灵感整理成三个行动步骤。'),
          ChatMessage.assistant(
            '当然可以。我们先从最容易开始的一步做起：\n\n1. **记下来**：用一句话描述你的想法。\n2. **试一试**：选一个今天能完成的小实验。\n3. **回头看**：记录结果，再决定下一步。\n\n你想先聊哪一个想法？',
          ),
        ],
      ),
    );
    await settings.init();
    await settings.update(apiKey: 'preview-only');
    await chat.init();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> screenshot(String name) async {
      expect(tester.takeException(), isNull);
      if (Platform.environment['DS_UI_CAPTURE'] != 'true') return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        await Directory('build/ui-review').create(recursive: true);
        await File('build/ui-review/$name.png').writeAsBytes(bytes);
        image.dispose();
      });
    }

    await screenshot('chat-light');
    Future<void> englishChat(String name) async {
      final messages = chat.messages;
      final original = messages.map((m) => m.content).toList();
      messages[0].content = 'Help me turn today’s idea into three steps.';
      messages[1].content = 'Let’s start with something small:\n\n1. **Write it down**: describe your idea in one sentence.\n2. **Try it out**: choose one small experiment you can finish today.\n3. **Look back**: note what you learned and decide what comes next.\n\nWhich idea would you like to explore?';
      await settings.updateAppearance(language: 'en');
      await tester.pumpAndSettle();
      await screenshot(name);
      for (var i = 0; i < messages.length; i++) {
        messages[i].content = original[i];
      }
      await settings.updateAppearance(language: 'zh_CN');
      await tester.pumpAndSettle();
    }

    await englishChat('chat-light-en');
    final composer = find.byKey(const ValueKey('message-composer'));
    expect(tester.getSize(composer).height, lessThanOrEqualTo(124));
    Future<void> captureMenu(String tooltip, String name) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Material &&
              w.clipBehavior == Clip.antiAlias &&
              w.shape is RoundedRectangleBorder &&
              (w.shape! as RoundedRectangleBorder).borderRadius ==
                  BorderRadius.circular(20),
        ),
        findsWidgets,
      );
      await screenshot(name);
      Navigator.of(tester.element(find.byType(PopupMenuItem<String>).first))
          .pop();
      await tester.pumpAndSettle();
    }

    await captureMenu('对话操作', 'chat-menu');
    await captureMenu('添加图片或文件', 'attachment-menu');
    await captureMenu('切换模型', 'model-menu');
    await settings.update(themeMode: 'dark');
    await tester.pumpAndSettle();
    await screenshot('chat-dark');
    await englishChat('chat-dark-en');
    // The wallpaper remains visible behind the shared chat surface.
    await settings.updateAppearance(color: 'ff227799');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('floating-top-bar')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!
          .a,
      closeTo(.92, .01),
    );
    final decoration =
        tester.widget<Container>(composer).decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(.82, .01));
    final bottomSurface = find.byKey(const ValueKey('chat-bottom-surface'));
    expect(tester.widget<ColoredBox>(bottomSurface).color, Colors.transparent);
    expect(tester.getBottomLeft(bottomSurface).dy, 844);
    final backdrop = find.byKey(const ValueKey('chat-backdrop'));
    expect(
      tester.getSize(backdrop),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await screenshot('chat-background');
    await settings.update(themeMode: 'light');
    await tester.pumpAndSettle();
    await screenshot('chat-background-light');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding(top: 24);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(bottomSurface).dy, 544);
    expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(544));
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    await settings.updateAppearance(color: '');
    await tester.pumpAndSettle();
    await settings.update(themeMode: 'light');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await screenshot('history');
    await captureMenu('更多', 'history-menu');
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await screenshot('settings');
    await settings.updateAppearance(language: 'en');
    await tester.pumpAndSettle();
    await screenshot('settings-en');
    await settings.updateAppearance(language: 'zh_CN');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-model')));
    await tester.pumpAndSettle();
    await screenshot('settings-model');
    await tester.tap(find.byKey(const ValueKey('section-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    final language = find.byKey(const ValueKey('language-setting'));
    await tester.ensureVisible(language);
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.text('主题立即生效')).dy,
      lessThan(tester.getTopLeft(language).dy),
    );
    await screenshot('appearance');
    await tester.tap(language);
    await tester.pumpAndSettle();
    await screenshot('language-picker');
    await tester.tap(find.byKey(const ValueKey('language-option-en')));
    await tester.pumpAndSettle();
    await screenshot('appearance-en');
    await tester.ensureVisible(
      find.byKey(const ValueKey('section-appearance')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-appearance')));
    await tester.pumpAndSettle();
    await screenshot('settings-dark');
    if (Platform.environment['DS_UI_CAPTURE'] == 'true') {
      await storage.saveConversation(
        Conversation(
          id: 'preview',
          messages: [
            for (var i = 0; i < 12; i++) ...[
              ChatMessage.user('第 ${i + 1} 个想法：怎样把灵感变成可以完成的小任务？'),
              ChatMessage.assistant(
                '先写下目标，再选择一个今天可以完成的步骤。\n\n保留过程中的记录，明天回看时就能找到下一步的方向。',
              ),
            ],
          ],
        ),
      );
      await chat.init();
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await settings.updateAppearance(language: 'zh_CN');
      await settings.update(themeMode: 'light');
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(195, 440), const Offset(0, 170));
      await tester.pumpAndSettle();
      await screenshot('chat-scroll-edges');
    }
    await tester.pumpWidget(const SizedBox());
    chat.dispose();
  });
}
