/// 一条联网检索来源。
///
/// 同时用于两处：
/// - 拼进发给模型的上下文（用 [summary]，官方说明它是"给模型读"的长摘要）
/// - 显示在回答下方（用 [snippet] 或 [title] + 域名）
class ChatSource {
  const ChatSource({
    required this.title,
    required this.url,
    this.snippet = '',
    this.siteName = '',
  });

  final String title;
  final String url;

  /// 100~200 字的短摘要，适合展示
  final String snippet;

  /// 站点名，可能为空
  final String siteName;

  /// 展示用的域名（解析失败时回退到完整 URL）
  String get domain {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.host;
  }

  /// 展示标题：没有标题时用域名
  String get displayTitle => title.trim().isEmpty ? domain : title.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'url': url,
    if (snippet.isNotEmpty) 'snippet': snippet,
    if (siteName.isNotEmpty) 'siteName': siteName,
  };

  factory ChatSource.fromJson(Map<String, dynamic> json) => ChatSource(
    title: (json['title'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    snippet: (json['snippet'] as String?) ?? '',
    siteName: (json['siteName'] as String?) ?? '',
  );

  static List<ChatSource> listFromJson(dynamic raw) {
    if (raw is! List) return const <ChatSource>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatSource.fromJson)
        .where((ChatSource s) => s.url.trim().isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(List<ChatSource> list) =>
      list.map((ChatSource s) => s.toJson()).toList();
}
