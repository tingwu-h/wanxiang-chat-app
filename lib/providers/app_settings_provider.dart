import 'package:flutter/foundation.dart';

import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/services/storage_service.dart';

/// 应用根状态：设置 + 主题模式 + 初始化状态。
///
/// Android 密钥持久化由 Keystore 保护，普通设置与密钥分开保存。
class AppSettingsProvider extends ChangeNotifier {
  AppSettingsProvider({required this._storage});

  final StorageService _storage;

  AppSettings _settings = AppSettings();
  bool _initialized = false;
  String? initializationWarning;

  AppSettings get settings => _settings;

  /// 是否已经把本地数据读进内存（main() 里会先 await init()）
  bool get initialized => _initialized;

  String get apiKey => _settings.apiKey;
  String get baseUrl => _settings.baseUrl;
  String get model => _settings.model;
  String get systemPrompt => _settings.systemPrompt;
  double get temperature => _settings.temperature;
  bool get hasApiKey => _settings.hasApiKey;

  /// 'system' | 'light' | 'dark'
  String get themeModeName => _settings.themeMode;

  Future<void> init() async {
    try {
      _settings = await _storage.loadSettings();
    } catch (_) {
      initializationWarning = '未能读取本机密钥，请重新填写。原聊天记录不受影响。';
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> replace(AppSettings next) async {
    await _storage.saveSettings(next);
    _settings = next;
    initializationWarning = null;
    notifyListeners();
  }

  void restoreRoute(String id, String? model) {
    _settings = _settings.forProvider(id).copyWith(model: model);
    notifyListeners();
  }

  Future<void> selectProvider(String id) => replace(_settings.forProvider(id));

  Future<void> update({
    String? apiKey,
    String? baseUrl,
    String? model,
    String? systemPrompt,
    double? temperature,
    String? themeMode,
  }) async {
    final next = _settings.copyWith(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
      systemPrompt: systemPrompt,
      temperature: temperature,
      themeMode: themeMode,
    );
    await _storage.saveSettings(next);
    _settings = next;
    initializationWarning = null;
    notifyListeners();
  }

  Future<void> updateAppearance({
    String? language,
    String? color,
    String? image,
    double? bubbleOpacity,
  }) => replace(
    _settings.copyWith(
      language: language,
      chatBackgroundColor: color,
      chatBackgroundImage: image,
      bubbleOpacity: bubbleOpacity,
    ),
  );

  /// 更新联网搜索相关设置。
  ///
  /// 单独成一个方法，是为了让设置页和聊天页的快捷开关
  /// 走同一条写入路径——两边联动，不会出现状态不一致。
  Future<void> updateSearch({
    bool? enabled,
    String? apiKey,
    int? count,
    bool? fetch,
    bool? showSources,
  }) => replace(
    _settings.copyWith(
      searchEnabled: enabled,
      searchApiKey: apiKey,
      searchCount: count,
      searchFetch: fetch,
      showSources: showSources,
    ),
  );

  /// 更新思考模式 / 推理强度 / 图片档位
  Future<void> updateModelBehaviour({
    bool? thinkingEnabled,
    String? reasoningEffort,
    String? imageDetail,
    bool? injectCurrentTime,
  }) => replace(
    _settings.copyWith(
      thinkingEnabled: thinkingEnabled,
      reasoningEffort: reasoningEffort,
      imageDetail: imageDetail,
      injectCurrentTime: injectCurrentTime,
    ),
  );

  /// 一键恢复默认（会同时清空 API Key）
  Future<void> resetToDefaults() => replace(AppSettings());
}
