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
    this.searchEnabled = false,
    this.searchApiKey = '',
    this.searchCount = defaultSearchCount,
    this.searchFetch = false,
    this.showSources = true,
    this.thinkingEnabled = true,
    this.reasoningEffort = defaultReasoningEffort,
    this.imageDetail = '',
    this.injectCurrentTime = true,
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

  /// 联网搜索：DeepSeek 的 Search / Fetch 是独立接口，
  /// 与当前对话模型无关，所以换任何厂商的模型都能用。
  static const int defaultSearchCount = 5;
  static const int minSearchCount = 1;
  static const int maxSearchCount = 50;

  /// 官方 Search 接口地址（与模型接口同域）
  static const String searchBaseUrl = 'https://api.deepseek.com';

  /// 思考模式的推理强度可选值（官方：low / high / max）
  static const String defaultReasoningEffort = 'high';
  static const List<String> reasoningEfforts = <String>['low', 'high', 'max'];

  /// 图片细节档位；空串表示不发送 detail（等同 original）
  static const List<String> imageDetailOptions = <String>['', 'low', 'original'];

  /// 默认模型。
  ///
  /// 取值依据官方文档 https://api-docs.deepseek.com/zh-cn/quick_start/pricing
  /// （2026 年当前页面只列 deepseek-flash 与 deepseek-v4-pro，
  ///   旧写法 deepseek-chat / deepseek-reasoner 已不在文档中）。
  /// 注意：这是文档值，本机没有有效 API Key，**未做真实调用验证**；
  /// 如果调用报「模型不存在」，用设置页的「自定义模型名」填上你账号可用的模型即可。
  static const String defaultModel = 'deepseek-flash';

  /// 预置模型（列表里可选的）
  ///
  /// v1.4.0 起移除 deepseek-chat / deepseek-reasoner：
  /// 官方文档当前只列 deepseek-flash 与 deepseek-v4-pro，
  /// 留着这两个旧名会让用户选中一个可能直接报错的模型。
  /// 需要它们的话仍可在设置页用「自定义模型名」填回去。
  static const List<String> availableModels = <String>[
    'deepseek-flash', // DeepSeek-V4.1-Flash-1017，官方推荐名，支持图片
    'deepseek-v4-pro', // DeepSeek-V4-Pro-0813，推理更强，不支持图片
  ];

  /// 每个模型在界面上的显示名
  static String modelLabel(String model) => switch (model) {
    'deepseek-flash' => 'deepseek-flash（快，日常对话）',
    'deepseek-v4-pro' => 'deepseek-v4-pro（强，复杂推理）',
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
      // 联网搜索 / 思考模式 / 图片档位都是应用级设置，
      // 切换服务商时不能丢，否则用户会以为开关失效。
      'searchEnabled': searchEnabled,
      'searchApiKey': searchApiKey,
      'searchCount': searchCount,
      'searchFetch': searchFetch,
      'showSources': showSources,
      'thinkingEnabled': thinkingEnabled,
      'reasoningEffort': reasoningEffort,
      'imageDetail': imageDetail,
      'injectCurrentTime': injectCurrentTime,
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

  /// 是否启用联网搜索（全局开关，与对话模型无关）
  final bool searchEnabled;

  /// 搜索专用 Key；为空时回落到 DeepSeek 服务商的 Key
  final String searchApiKey;

  /// 每次搜索返回的结果条数
  final int searchCount;

  /// 是否对搜索结果调用 Fetch 抓取完整正文
  final bool searchFetch;

  /// 是否在回答下方显示来源链接
  final bool showSources;

  /// DeepSeek 思考模式开关（官方默认开启）
  final bool thinkingEnabled;

  /// 推理强度：low / high / max
  final String reasoningEffort;

  /// 图片细节档位：'' / low / original
  final String imageDetail;

  /// 是否把当前日期时间注入系统提示词。
  ///
  /// 模型本身不知道「今天」是哪天，不注入就只能回答「无法确定当前日期」。
  /// 默认开启；用户可以关掉，但关掉后日期类问题会退回到猜测。
  final bool injectCurrentTime;

  /// 实际用于搜索的 Key：优先专用 Key，否则复用 DeepSeek 那家的
  String get effectiveSearchApiKey {
    final String own = searchApiKey.trim();
    if (own.isNotEmpty) return own;
    if (providerId == 'deepseek') return apiKey.trim();
    final Object? deepseekProfile = profiles['deepseek'];
    if (deepseekProfile is Map) {
      final Object? k = deepseekProfile['apiKey'];
      if (k is String) return k.trim();
    }
    return '';
  }

  /// 联网搜索是否可用（需要 Key）
  bool get canSearch => effectiveSearchApiKey.isNotEmpty;

  /// DeepSeek 是否当前处于思考模式
  ///
  /// 只有 DeepSeek 服务商受这个开关影响；其它厂商走各自默认行为。
  bool get isThinkingActive => providerId == 'deepseek' && thinkingEnabled;

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
    bool? searchEnabled,
    String? searchApiKey,
    int? searchCount,
    bool? searchFetch,
    bool? showSources,
    bool? thinkingEnabled,
    String? reasoningEffort,
    String? imageDetail,
    bool? injectCurrentTime,
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
      searchEnabled: searchEnabled ?? this.searchEnabled,
      searchApiKey: searchApiKey ?? this.searchApiKey,
      searchCount: searchCount ?? this.searchCount,
      searchFetch: searchFetch ?? this.searchFetch,
      showSources: showSources ?? this.showSources,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      imageDetail: imageDetail ?? this.imageDetail,
      injectCurrentTime: injectCurrentTime ?? this.injectCurrentTime,
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
    'searchEnabled': searchEnabled,
    'searchApiKey': searchApiKey,
    'searchCount': searchCount,
    'searchFetch': searchFetch,
    'showSources': showSources,
    'thinkingEnabled': thinkingEnabled,
    'reasoningEffort': reasoningEffort,
    'imageDetail': imageDetail,
    'injectCurrentTime': injectCurrentTime,
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
      searchEnabled: json['searchEnabled'] == true,
      searchApiKey: (json['searchApiKey'] as String?) ?? '',
      searchCount: _clampSearchCount(json['searchCount']),
      searchFetch: json['searchFetch'] == true,
      // 缺失时默认显示来源（老用户升级后联网一旦开启就有来源可看）
      showSources: json['showSources'] is bool
          ? json['showSources'] as bool
          : true,
      // 官方默认开启思考模式，缺失时保持开启以对齐官方行为
      thinkingEnabled: json['thinkingEnabled'] is bool
          ? json['thinkingEnabled'] as bool
          : true,
      reasoningEffort: reasoningEfforts.contains(json['reasoningEffort'])
          ? json['reasoningEffort'] as String
          : defaultReasoningEffort,
      imageDetail: imageDetailOptions.contains(json['imageDetail'])
          ? json['imageDetail'] as String
          : '',
      // 缺失时默认开启：升级用户也能立刻获得正确的日期回答
      injectCurrentTime: json['injectCurrentTime'] is bool
          ? json['injectCurrentTime'] as bool
          : true,
    );
  }

  /// 结果条数夹到 1~50（官方限制），非法值回落默认
  static int _clampSearchCount(Object? raw) {
    final int? v = (raw as num?)?.toInt();
    if (v == null) return defaultSearchCount;
    return v.clamp(minSearchCount, maxSearchCount);
  }

  /// 把持久化读到的值夹到合法范围；非法/缺失用默认值。
  static double _clampOpacity(Object? raw) {
    final double? v = (raw as num?)?.toDouble();
    if (v == null || v.isNaN) return defaultBubbleOpacity;
    return v.clamp(minBubbleOpacity, maxBubbleOpacity);
  }
}
