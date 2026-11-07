/// 检索词组装。
///
/// 单独抽出来是为了能直接单测：联网时搜什么，直接决定来源是否对题。
/// 原则：
/// - 自包含的问题原样搜；
/// - 只有“离开上一句就看不懂”的追问，才把上一轮用户问题补进来；
/// - 当前句始终放在最前面，旧问题只补语境；
/// - 合并不带助手回答、不累积历史，长度封顶 128 字。
class SearchQueryBuilder {
  SearchQueryBuilder._();

  /// 官方接口 query 的长度上限（Unicode 字符）
  static const int maxQueryLength = 128;

  /// 追问句式的开头。命中且长度不超过 [_followUpMaxLength] 才合并。
  static const List<String> _followUpPrefixes = <String>[
    '那',
    '所以',
    '但是',
    '然后',
    '还有',
    '继续',
    '详细',
    '展开',
    '再说',
    '具体',
    '它',
    '这个',
    '那个',
    '刚才',
    '上面',
    '为什么',
    '为啥',
    '怎么',
    '咋',
  ];

  /// 超过这个长度就不再当追问，避免把完整的新问题拼上旧话题。
  static const int _followUpMaxLength = 20;

  /// 极短消息（「为什么」「展开」）一律视为追问。
  static const int _shortMessageLength = 6;

  static bool isFollowUp(String text) {
    final String t = text.trim();
    if (t.isEmpty) return false;
    if (t.length <= _shortMessageLength) return true;
    if (t.length > _followUpMaxLength) return false;
    return _followUpPrefixes.any(t.startsWith);
  }

  /// 组装最终检索词。[previous] 传上一轮用户问题，没有就传 null。
  static String build({required String current, String? previous}) {
    final String now = current.trim();
    final String prev = (previous ?? '').trim();
    if (now.isEmpty) return _head(prev);
    if (prev.isEmpty || !isFollowUp(now)) return _head(now);
    // 当前句在前：搜索引擎对靠前的词权重更高，旧问题只在后面补语境。
    return _head('$now $prev');
  }

  static String _head(String text) =>
      text.length <= maxQueryLength ? text : text.substring(0, maxQueryLength);
}
