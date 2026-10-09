import 'package:deepseek_chat/models/provider_catalog.dart';

/// 内存设置模型；落盘时密钥与普通设置分开保存。
class AppSettings {
  AppSettings({
    this.providerId = 'deepseek',
    this.protocol = 'openai',
    this.imageSupport,
    this.profiles = const {},
    this.savedModels = const [],
    this.apiKey = '',
    this.baseUrl = defaultBaseUrl,
    this.model = defaultModel,
    this.systemPrompt = '',
    this.temperature = 1.0,
    this.themeMode = 'system',
    this.language = 'zh_CN',
    this.chatBackgroundColor = '',
    this.chatBackgroundImage = '',
    this.bubbleOpacity = defaultBubbleOpacity,
  });

  /// DeepSeek 官方 API 基地址
  static const String defaultBaseUrl = 'https://api.deepseek.com';

  /// 聊天气泡不透明度的默认值与可选范围。
  ///
  /// 气泡改成磨砂玻璃后半透明，用户自定义的背景图才不会被消息盖住；
  /// 但文字可读性优先，所以下限不给到全透明。
  static const double defaultBubbleOpacity = 0.8;
  static const double minBubbleOpacity = 0.3;
  static const double maxBubbleOpacity = 1.0;

  /// 默认模型。
  ///
  /// 取值依据官方文档 https://api-docs.deepseek.com/zh-cn/quick_start/pricing
  /// （2026 年当前页面只列 deepseek-flash 与 deepseek-v4-pro，
  ///   旧写法 deepseek-chat / deepseek-reasoner 已不在文档中）。
  /// 注意：这是文档值，本机没有有效 API Key，**未做真实调用验证**；
  /// 如果调用报「模型不存在」，用设置页的「自定义模型名」填上你账号可用的模型即可。
  static const String defaultModel = 'deepseek-flash';

  /// 预置模型（列表里可选的）
  static const List<String> availableModels = <String>[
    'deepseek-flash', // DeepSeek-V4.1-Flash，官方文档推荐名
    'deepseek-v4-pro', // DeepSeek-V4-Pro-0813，推理更强
    'deepseek-chat', // 上一代写法，仍被 API 接受（文档未列）
    'deepseek-reasoner', // 上一代推理模型写法
  ];

  /// 每个模型在界面上的显示名
  static String modelLabel(String model) => switch (model) {
    'deepseek-flash' => 'deepseek-flash（快，日常对话）',
    'deepseek-v4-pro' => 'deepseek-v4-pro（强，复杂推理）',
    'deepseek-chat' => 'deepseek-chat（上一代·通用）',
    'deepseek-reasoner' => 'deepseek-reasoner（上一代·推理）',
    _ => model,
  };

  /// 顶栏胶囊里的短名
  static String modelShortName(String model) {
    if (model.startsWith('deepseek-')) {
      final String rest = model.substring('deepseek-'.length);
      return rest.length <= 10 ? rest : '${rest.substring(0, 10)}…';
    }
    return model.length <= 10 ? model : '${model.substring(0, 10)}…';
  }

  /// 主题模式：system / light / dark
  static const List<String> availableThemeModes = <String>[
    'system',
    'light',
    'dark',
  ];

  final List<String> savedModels;
  final String providerId;
  final String protocol;
  final bool? imageSupport;
  final Map<String, Map<String, dynamic>> profiles;
  bool get supportsImages => imageSupport ?? modelSupportsImages(model);
  ProviderPreset get preset => presetFor(providerId);
  List<String> get modelChoices => {
    ...preset.models,
    ...savedModels,
    model,
  }.where((m) => m.isNotEmpty).toList();

  AppSettings forProvider(String id) {
    if (id == providerId) return this;
    final saved = {...profiles, providerId: profileJson()};
    final p = presetFor(id);
    final data =
        saved[id] ??
        {
          'providerId': id,
          'protocol': p.protocol,
          'apiKey': '',
          'baseUrl': p.url,
          'model': p.models.isEmpty ? '' : p.models.first,
        };
    return AppSettings.fromJson({
      ...data,
      'providerId': id,
      'profiles': saved,
      'themeMode': themeMode,
      'systemPrompt': systemPrompt,
      'language': language,
      'chatBackgroundColor': chatBackgroundColor,
      'chatBackgroundImage': chatBackgroundImage,
    });
  }

  Map<String, dynamic> profileJson() => {
    'savedModels': savedModels,
    'providerId': providerId,
    'protocol': protocol,
    'imageSupport': imageSupport,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'model': model,
    'temperature': temperature,
  };

  final String apiKey;
  final String baseUrl;
  final String model;
  final String systemPrompt;
  final double temperature;
  final String themeMode;
  final String language;
  final String chatBackgroundColor;
  final String chatBackgroundImage;

  /// 聊天气泡的不透明度（0.3 ~ 1.0）。越透明越能看见自定义背景。
  final double bubbleOpacity;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 只用于界面展示，避免完整 Key 出现在截图里
  String get maskedApiKey {
    final String k = apiKey.trim();
    if (k.isEmpty) return '未设置';
    if (k.length <= 2) return '****';
    if (k.length <= 10) return '${k.substring(0, 2)}****';
    return '${k.substring(0, 6)}****${k.substring(k.length - 4)}';
  }

  AppSettings copyWith({
    String? providerId,
    String? protocol,
    bool? imageSupport,
    Map<String, Map<String, dynamic>>? profiles,
    String? apiKey,
    String? baseUrl,
    String? model,
    String? systemPrompt,
    double? temperature,
    String? themeMode,
    String? language,
    String? chatBackgroundColor,
    String? chatBackgroundImage,
    double? bubbleOpacity,
  }) {
    return AppSettings(
      savedModels: {
        ...savedModels,
        this.model,
        if (model != null) model,
      }.where((m) => m.isNotEmpty).toList(),
      providerId: providerId ?? this.providerId,
      protocol: protocol ?? this.protocol,
      imageSupport:
          imageSupport ??
          (model != null && model != this.model ? null : this.imageSupport),
      profiles: profiles ?? this.profiles,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      chatBackgroundColor: chatBackgroundColor ?? this.chatBackgroundColor,
      chatBackgroundImage: chatBackgroundImage ?? this.chatBackgroundImage,
      bubbleOpacity: bubbleOpacity ?? this.bubbleOpacity,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'savedModels': savedModels,
    'providerId': providerId,
    'protocol': protocol,
    'imageSupport': imageSupport,
    'profiles': profiles,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'model': model,
    'systemPrompt': systemPrompt,
    'temperature': temperature,
    'themeMode': themeMode,
    'language': language,
    'chatBackgroundColor': chatBackgroundColor,
    'chatBackgroundImage': chatBackgroundImage,
    'bubbleOpacity': bubbleOpacity,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      savedModels: List<String>.from(json['savedModels'] as List? ?? []),
      providerId: json['providerId'] as String? ?? 'deepseek',
      protocol: json['protocol'] as String? ?? 'openai',
      imageSupport: json['imageSupport'] as bool?,
      profiles: (json['profiles'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      ),
      apiKey: (json['apiKey'] as String?) ?? '',
      baseUrl: (json['baseUrl'] as String?) ?? defaultBaseUrl,
      model: (json['model'] as String?) ?? defaultModel,
      systemPrompt: (json['systemPrompt'] as String?) ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
      themeMode: (json['themeMode'] as String?) ?? 'system',
      language: ['zh_CN', 'zh_TW', 'en'].contains(json['language'])
          ? json['language'] as String
          : 'zh_CN',
      chatBackgroundColor: json['chatBackgroundColor'] as String? ?? '',
      chatBackgroundImage: json['chatBackgroundImage'] as String? ?? '',
      // 越界或缺失都回落到默认值，避免旧数据把气泡弄成全透明
      bubbleOpacity: _clampOpacity(json['bubbleOpacity']),
    );
  }

  /// 把持久化读到的值夹到合法范围；非法/缺失用默认值。
  static double _clampOpacity(Object? raw) {
    final double? v = (raw as num?)?.toDouble();
    if (v == null || v.isNaN) return defaultBubbleOpacity;
    return v.clamp(minBubbleOpacity, maxBubbleOpacity);
  }
}
