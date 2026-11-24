/// 一条用户自定义的指令插件（“破甲”属于其中一种用法）。
///
/// 只在请求组装时拼接，不写进会话历史，也不改变 API 参数。
class PromptPlugin {
  const PromptPlugin({
    required this.id,
    required this.name,
    required this.body,
    this.enabled = true,
    this.priority = 0,
    this.builtin = false,
  });

  /// 单条正文上限
  static const int maxBodyChars = 4000;

  /// 所有启用插件合计上限
  static const int maxTotalChars = 8000;

  final String id;
  final String name;
  final String body;
  final bool enabled;

  /// 越小越靠前；相同值保持列表顺序。
  final int priority;

  /// 是否随 App 内置。内置项不可编辑、不可删除，只能开关或复制。
  final bool builtin;

  bool get isUsable => enabled && body.trim().isNotEmpty;

  PromptPlugin copyWith({
    String? id,
    String? name,
    String? body,
    bool? enabled,
    int? priority,
    bool? builtin,
  }) => PromptPlugin(
    id: id ?? this.id,
    name: name ?? this.name,
    body: body ?? this.body,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    builtin: builtin ?? this.builtin,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'body': body,
    'enabled': enabled,
    'priority': priority,
    if (builtin) 'builtin': true,
  };

  factory PromptPlugin.fromJson(Map<String, dynamic> json) => PromptPlugin(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    priority: (json['priority'] as num?)?.toInt() ?? 0,
    builtin: json['builtin'] == true,
  );

  static List<PromptPlugin> listFromJson(dynamic raw) {
    if (raw is! List) return const <PromptPlugin>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PromptPlugin.fromJson)
        .where((PromptPlugin p) => p.id.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(List<PromptPlugin> list) =>
      list.map((PromptPlugin p) => p.toJson()).toList();
}
