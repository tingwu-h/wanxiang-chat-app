import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:deepseek_chat/services/update_service.dart';

void main() {
  group('版本比较', () {
    test('新版 / 同版 / 旧版', () {
      expect(UpdateService.compareVersions('1.6.0', '1.5.1'), greaterThan(0));
      expect(UpdateService.compareVersions('1.5.1', '1.5.1'), 0);
      expect(UpdateService.compareVersions('1.5.0', '1.5.1'), lessThan(0));
      expect(UpdateService.compareVersions('v1.6.0', '1.5.9'), greaterThan(0));
    });

    test('段数不同按 0 补齐', () {
      expect(UpdateService.compareVersions('1.5', '1.5.0'), 0);
      expect(UpdateService.compareVersions('1.5.1', '1.5'), greaterThan(0));
    });
  });

  group('检测更新', () {
    UpdateService serviceWith(MockClient client) =>
        UpdateService(client: client);

    test('解析最新版本', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, Object>{
                'tag_name': 'v1.6.0',
                'html_url': 'https://example.com/release',
                'body': '更新说明',
                'published_at': '2026-12-01T00:00:00Z',
              }),
            ),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );
      final UpdateInfo info = await service.latest();
      expect(info.version, '1.6.0');
      expect(info.url, 'https://example.com/release');
      expect(info.body, '更新说明');
    });

    test('非 200 抛出可读错误', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async => http.Response('', 500)),
      );
      expect(
        () => service.latest(),
        throwsA(
          isA<UpdateException>().having(
            (UpdateException e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });

    test('缺少 tag_name 报错', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async {
          return http.Response(jsonEncode(<String, Object>{}), 200);
        }),
      );
      expect(() => service.latest(), throwsA(isA<UpdateException>()));
    });

    test('不是 JSON 报错', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async => http.Response('oops', 200)),
      );
      expect(() => service.latest(), throwsA(isA<UpdateException>()));
    });
    test('403 限流时回退到发布页跳转', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response('rate limited', 403);
          }
          return http.Response('', 302, headers: <String, String>{
            'location':
                'https://github.com/tingwu-h/wanxiang-chat-app/releases/tag/v1.7.0',
          });
        }),
      );
      final UpdateInfo info = await service.latest();
      expect(info.version, '1.7.0');
      expect(info.url, contains('/releases/tag/v1.7.0'));
    });

    test('发布页没有版本号时报错', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response('rate limited', 429);
          }
          return http.Response('ok', 200);
        }),
      );
      expect(() => service.latest(), throwsA(isA<UpdateException>()));
    });

    test('非限流的 500 不回退', () async {
      final UpdateService service = serviceWith(
        MockClient((http.Request request) async => http.Response('', 500)),
      );
      expect(() => service.latest(), throwsA(isA<UpdateException>()));
    });
  });
}
