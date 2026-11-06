import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:deepseek_chat/pages/about_page.dart';
import 'package:deepseek_chat/pages/model_behaviour_page.dart';
import 'package:deepseek_chat/pages/search_settings_page.dart';
import 'package:deepseek_chat/pages/chat_page.dart';
import 'package:deepseek_chat/pages/settings_page.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/providers/chat_provider.dart';
import 'package:deepseek_chat/services/deepseek_service.dart';
import 'package:deepseek_chat/services/storage_service.dart';
import 'package:deepseek_chat/theme/app_theme.dart';

Future<void> main() async {
  // 初始化 Flutter 引擎（shared_preferences 需要）
  WidgetsFlutterBinding.ensureInitialized();

  // 启动时先把本地数据读出来，避免界面先闪一下空列表
  final StorageService storage = StorageService();
  final AppSettingsProvider settingsProvider = AppSettingsProvider(
    storage: storage,
  );
  final ChatProvider chatProvider = ChatProvider(
    api: DeepSeekService(),
    storage: storage,
  );
  await Future.wait<void>(<Future<void>>[
    settingsProvider.init(),
    chatProvider.init(),
  ]);

  if (chatProvider.activeProviderId case final String id) {
    settingsProvider.restoreRoute(id, chatProvider.activeModel);
  }

  runApp(
    DeepSeekChatApp(
      settingsProvider: settingsProvider,
      chatProvider: chatProvider,
    ),
  );
}

/// 应用根组件：注入 Provider、管理主题（含深色模式）与路由。
class DeepSeekChatApp extends StatelessWidget {
  const DeepSeekChatApp({
    super.key,
    required this.settingsProvider,
    required this.chatProvider,
  });

  final AppSettingsProvider settingsProvider;
  final ChatProvider chatProvider;

  ThemeMode _themeModeFor(String name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // 类型由 providers 参数推断（List<SingleChildWidget>），无需额外 import
      providers: [
        ChangeNotifierProvider<AppSettingsProvider>.value(
          value: settingsProvider,
        ),
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
      ],
      // Consumer 负责在「设置页改了主题」后重建 MaterialApp
      child: Consumer<AppSettingsProvider>(
        builder: (BuildContext context, AppSettingsProvider settings, _) {
          return MaterialApp(
            title: '万象',
            locale: switch (settings.settings.language) {
              'en' => const Locale('en'),
              'zh_TW' => const Locale('zh', 'TW'),
              _ => const Locale('zh', 'CN'),
            },
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('en'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            debugShowCheckedModeBanner: false,
            themeMode: _themeModeFor(settings.themeModeName),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            home: const ChatPage(),
            routes: <String, WidgetBuilder>{
              SettingsPage.routeName: (_) => const SettingsPage(),
              SearchSettingsPage.routeName: (_) => const SearchSettingsPage(),
              ModelBehaviourPage.routeName: (_) => const ModelBehaviourPage(),
              AboutPage.routeName: (_) => const AboutPage(),
            },
          );
        },
      ),
    );
  }
}
