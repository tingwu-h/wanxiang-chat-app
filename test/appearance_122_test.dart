import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deepseek_chat/main.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/conversation.dart';
import 'package:deepseek_chat/pages/image_editor_page.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/image_processing_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('wanxiang-image-test-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('deepseek_chat/platform'),
          null,
        );
    await temp.delete(recursive: true);
  });

  test(
    'appearance persists, survives provider changes, and defaults migrate',
    () async {
      final storage = StorageService();
      final provider = AppSettingsProvider(storage: storage);
      await provider.init();
      await provider.update(apiKey: 'fixture');
      await provider.updateAppearance(
        language: 'zh_TW',
        color: 'ff202734',
        image: '${temp.path}/background.png',
      );
      await provider.selectProvider('google');
      final restored = await storage.loadSettings();
      expect(restored.language, 'zh_TW');
      expect(restored.chatBackgroundColor, 'ff202734');
      expect(restored.chatBackgroundImage, endsWith('/background.png'));
      expect(restored.forProvider('deepseek').apiKey, 'fixture');
      expect(AppSettings.fromJson({}).language, 'zh_CN');
      expect(AppSettings.fromJson({'language': 'invalid'}).language, 'zh_CN');
    },
  );

  test('clearing history preserves separately stored background', () async {
    final file = await File('${temp.path}/background.png')
        .writeAsBytes([1, 2, 3]);
    final storage = StorageService();
    await storage.saveSettings(AppSettings(chatBackgroundImage: file.path));
    await storage.saveConversation(
      Conversation(id: 'test', messages: [ChatMessage.user('test')]),
    );
    await storage.deleteAllConversations();
    expect(await file.exists(), isTrue);
    expect((await storage.loadSettings()).chatBackgroundImage, file.path);
  });

  test(
    'large output invokes compression; failure removes partial files',
    () async {
      var compressed = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('deepseek_chat/platform'),
            (call) async {
              expect(call.method, 'compressImage');
              final args = Map<String, dynamic>.from(call.arguments as Map);
              expect(
                await File(args['path'] as String).length(),
                greaterThan(ImageProcessingService.maxBytes),
              );
              final output = await File(args['output'] as String)
                  .writeAsBytes([0xff, 0xd8, 0xff]);
              compressed++;
              return output.path;
            },
          );
      final small = await ImageProcessingService.save(Uint8List(100));
      expect(compressed, 0);
      final large = await ImageProcessingService.save(
        Uint8List(ImageProcessingService.maxBytes + 1),
      );
      expect(compressed, 1);
      expect(large.path, endsWith('.jpg'));
      expect(
        await large.length(),
        lessThanOrEqualTo(ImageProcessingService.maxBytes),
      );
      final before = await Directory('${temp.path}/attachments').list().length;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('deepseek_chat/platform'),
            (_) async => throw PlatformException(code: 'FAILED'),
          );
      await expectLater(
        ImageProcessingService.save(
          Uint8List(ImageProcessingService.maxBytes + 1),
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(await Directory('${temp.path}/attachments').list().length, before);
      expect(await small.exists(), isTrue);
    },
  );

  testWidgets(
    'language switch translates app and native copy menu immediately',
    (tester) async {
      final storage = StorageService();
      final settings = AppSettingsProvider(storage: storage);
      await settings.init();
      final chat = ChatProvider(api: DeepSeekService(), storage: storage);
      await chat.init();
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        DeepSeekChatApp(settingsProvider: settings, chatProvider: chat),
      );
      await tester.pumpAndSettle();
      BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(MaterialLocalizations.of(context).copyButtonLabel, '复制');
      await settings.updateAppearance(language: 'en');
      await tester.pumpAndSettle();
      context = tester.element(find.byType(Scaffold).first);
      expect(MaterialLocalizations.of(context).copyButtonLabel, 'Copy');
      expect(find.text('New chat'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-appearance')));
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const ValueKey('language-setting'));
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('繁體中文'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language-option-zh_TW')));
      await tester.pumpAndSettle();
      expect(settings.settings.language, 'zh_TW');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('設定'), findsOneWidget);
      context = tester.element(find.byType(SettingsPage));
      expect(MaterialLocalizations.of(context).copyButtonLabel, '複製');
      for (final code in ['en', 'zh_CN', 'zh_TW']) {
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('language-option-$code')));
        await tester.pumpAndSettle();
        expect(settings.settings.language, code);
        expect(find.byType(BottomSheet), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image editor crops, enlarges and saves without touching original',
    (tester) async {
      late String input;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 80, 40),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(80, 40);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        input = '${temp.path}/original.png';
        await File(input).writeAsBytes(data!.buffer.asUint8List());
        picture.dispose();
        image.dispose();
      });
      File? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await ImageEditorPage.open(context, input),
              child: const Text('Edit'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Edit'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      for (
        var i = 0;
        i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('1:1'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<double>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2×').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 50 && result == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          await result!.readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        expect((image.width, image.height), (80, 80));
        image.dispose();
        codec.dispose();
        final original = await ui.instantiateImageCodec(
          await File(input).readAsBytes(),
        );
        final originalImage = (await original.getNextFrame()).image;
        expect((originalImage.width, originalImage.height), (80, 40));
        originalImage.dispose();
        original.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );
}
