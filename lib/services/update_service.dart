import 'dart:convert';

import 'package:http/http.dart' as http;

/// GitHub Releases 检测更新。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.body,
    this.publishedAt = '',
  });

  final String version;
  final String url;
  final String body;
  final String publishedAt;
}

class UpdateException implements Exception {
  UpdateException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get rateLimited => statusCode == 403 || statusCode == 429;

  @override
  String toString() => message;
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const String repo = 'tingwu-h/wanxiang-chat-app';
  static const String releasesUrl =
      'https://github.com/tingwu-h/wanxiang-chat-app/releases/latest';

  final http.Client _client;

  /// 先走 API；403/429 时退回发布页跳转，避免未认证限流导致永远失败。
  Future<UpdateInfo> latest() async {
    try {
      return await _fromApi();
    } on UpdateException catch (e) {
      if (!e.rateLimited) rethrow;
      return _fromRedirect();
    }
  }

  Future<UpdateInfo> _fromApi() async {
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/$repo/releases/latest',
    );
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Wanxiang-Android',
            },
          )
          .timeout(const Duration(seconds: 10));
    } on Exception {
      throw UpdateException('检查更新失败，请检查网络后重试。');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw UpdateException(
        'GitHub 接口限流（${response.statusCode}），正在改用发布页检查。',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw UpdateException(
        '检查更新失败（${response.statusCode}）。',
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } on FormatException {
      throw UpdateException('更新信息格式不正确。');
    }
    if (decoded is! Map<String, dynamic>) {
      throw UpdateException('更新信息格式不正确。');
    }
    final String tag = (decoded['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) throw UpdateException('没有找到版本号。');
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      url:
          (decoded['html_url'] as String?) ??
          'https://github.com/$repo/releases',
      body: (decoded['body'] as String? ?? '').trim(),
      publishedAt: (decoded['published_at'] as String? ?? ''),
    );
  }

  /// 不调用 API，直接跟随 `releases/latest` 的 302，从 Location 里取版本。
  Future<UpdateInfo> _fromRedirect() async {
    Uri current = Uri.parse(releasesUrl);
    try {
      for (int hop = 0; hop < 5; hop++) {
        final http.Request request = http.Request('GET', current)
          ..followRedirects = false
          ..headers['User-Agent'] = 'Wanxiang-Android';
        final http.StreamedResponse response = await _client
            .send(request)
            .timeout(const Duration(seconds: 10));
        final String? location = response.headers['location'];
        if (response.statusCode >= 300 &&
            response.statusCode < 400 &&
            location != null &&
            location.isNotEmpty) {
          current = current.resolve(location);
          continue;
        }
        break;
      }
    } on Exception {
      throw UpdateException('检查更新失败，请检查网络后重试。');
    }

    final RegExpMatch? match = RegExp(
      r'/releases/tag/([^/?#]+)',
    ).firstMatch(current.toString());
    if (match == null) {
      throw UpdateException('检查更新失败，请稍后重试。');
    }
    final String tag = Uri.decodeComponent(match.group(1)!);
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      url: current.toString(),
      body: '',
    );
  }

  /// 逐段比较数字，返回 >0 表示 [a] 比 [b] 新。
  static int compareVersions(String a, String b) {
    List<int> parse(String value) => value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[.+-]'))
        .map((String part) => int.tryParse(part) ?? 0)
        .toList();
    final List<int> left = parse(a);
    final List<int> right = parse(b);
    final int length = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < length; i++) {
      final int l = i < left.length ? left[i] : 0;
      final int r = i < right.length ? right[i] : 0;
      if (l != r) return l - r;
    }
    return 0;
  }

  void dispose() => _client.close();
}
