import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/models/chat_message.dart';
import 'package:deepseek_chat/models/prompt_plugin.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/builtin_plugins.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/utils/prompt_assembler.dart';

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

void main() {
  test('内置破甲存在且默认启用', () {
    expect(kBuiltinPlugins.single.id, 'pojia');
    expect(kBuiltinPlugins.single.builtin, isTrue);
    expect(kBuiltinPlugins.single.body, contains('最高优先级指令'));

    final AppSettings settings = AppSettings();
    expect(settings.enabledBuiltinPlugins, contains('pojia'));
  });

  test('旧数据升级后默认启用内置破甲', () {
    final AppSettings settings = AppSettings.fromJson(<String, dynamic>{});
    expect(settings.enabledBuiltinPlugins, contains('pojia'));
  });

  test('内置排在自定义之前，即使自定义 priority 为 0', () {
    final AppSettings settings = AppSettings(
      plugins: <PromptPlugin>[
        const PromptPlugin(id: 'c', name: '自定义', body: '自定义正文'),
      ],
    );
    final List<PromptPlugin> resolved = PromptAssembler.resolve(
      settings,
      null,
    );
    expect(resolved.first.id, 'pojia');
    expect(resolved.last.id, 'c');

    final String prompt = PromptAssembler.build(
      plugins: resolved,
      dateLine: '',
      basePrompt: '',
      searchContext: '',
      overrideAppLines: false,
    );
    expect(prompt, startsWith('【最高优先级指令'));
    expect(prompt.indexOf('自定义正文'), greaterThan(0));
  });

  test('关闭内置后不再注入', () {
    final AppSettings settings = AppSettings(
      enabledBuiltinPlugins: const <String>[],
    );
    final List<PromptPlugin> resolved = PromptAssembler.resolve(
      settings,
      null,
    );
    expect(resolved, isEmpty);

    final String prompt = PromptAssembler.build(
      plugins: resolved,
      dateLine: '时间行',
      basePrompt: '',
      searchContext: '',
      overrideAppLines: false,
    );
    expect(prompt, '时间行');
  });

  test('会话指定只启用内置时，自定义不生效', () {
    final AppSettings settings = AppSettings(
      plugins: <PromptPlugin>[
        const PromptPlugin(id: 'c', name: '自定义', body: '自定义正文'),
      ],
    );
    final List<PromptPlugin> resolved = PromptAssembler.resolve(
      settings,
      <String>['pojia'],
    );
    expect(resolved.single.id, 'pojia');
  });

  test('内置正文不写进设置 JSON', () {
    final String json = jsonEncode(AppSettings().toJson());
    expect(json, contains('pojia'));
    expect(json, isNot(contains('最高优先级指令')));
  });

  test('复制出来的副本是自定义插件', () {
    final PromptPlugin copy = kBuiltinPlugins.single.copyWith(
      id: 'copy',
      name: '破甲（副本）',
      builtin: false,
    );
    expect(copy.builtin, isFalse);
    expect(copy.body, kBuiltinPlugins.single.body);
    expect(copy.toJson().containsKey('builtin'), isFalse);
  });

  test('默认发送时 system prompt 以破甲开头', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final StorageService storage = StorageService(
      readKey: () async => null,
      writeKey: (String _) async {},
    );
    final CapturingApi api = CapturingApi();
    final ChatProvider provider = ChatProvider(api: api, storage: storage);
    await provider.init();

    await provider.send(
      '你好',
      AppSettings(model: 'deepseek-flash', apiKey: 'k'),
    );

    expect(api.captured!.systemPrompt, startsWith('【最高优先级指令'));
    expect(api.captured!.systemPrompt, contains('当前时间是'));
  });
}
