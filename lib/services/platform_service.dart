import 'dart:io';

import 'package:flutter/services.dart';

/// Desktop implementations can provide secure storage and export without changing chat code.
abstract interface class PlatformBackend {
  Future<String?> readKey();
  Future<void> writeKey(String value);
  Future<bool> exportHistory(String json);
  Future<bool> exportChatText(String text);
  Future<void> goToDesktop();
}

class AndroidPlatformBackend implements PlatformBackend {
  static const channel = MethodChannel('deepseek_chat/platform');
  @override
  Future<String?> readKey() => channel.invokeMethod<String>('readKey');
  @override
  Future<void> writeKey(String value) =>
      channel.invokeMethod<void>('writeKey', value);
  @override
  Future<bool> exportHistory(String json) async =>
      await channel.invokeMethod<bool>('exportHistory', json) ?? false;
  @override
  Future<bool> exportChatText(String text) async =>
      await channel.invokeMethod<bool>('exportChatText', text) ?? false;
  @override
  Future<void> goToDesktop() => channel.invokeMethod<void>('goToDesktop');
}

/// Non-Android development fallback. Never persists credentials as plaintext.
class SessionPlatformBackend implements PlatformBackend {
  String? _key;
  @override
  Future<String?> readKey() async => _key;
  @override
  Future<void> writeKey(String value) async {
    _key = value;
  }

  @override
  Future<bool> exportHistory(String json) async =>
      throw UnsupportedError('当前平台尚未实现导出');
  @override
  Future<bool> exportChatText(String text) async =>
      throw UnsupportedError('当前平台尚未实现导出');
  @override
  Future<void> goToDesktop() async => SystemNavigator.pop();
}

class PlatformService {
  static const channel = AndroidPlatformBackend.channel;
  static PlatformBackend backend = Platform.isAndroid
      ? AndroidPlatformBackend()
      : SessionPlatformBackend();
  static Future<String?> readKey() => backend.readKey();
  static Future<void> writeKey(String value) => backend.writeKey(value);
  static Future<bool> exportHistory(String json) => backend.exportHistory(json);
  static Future<bool> exportChatText(String text) => backend.exportChatText(text);
  static Future<void> goToDesktop() => backend.goToDesktop();
}
