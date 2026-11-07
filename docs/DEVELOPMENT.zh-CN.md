# 万象开发与构建指南

## 从源码运行

项目使用 Flutter + Provider。当前版本 **v1.4.5**（构建号 27），已在 Flutter **3.47.5**、Dart **3.13.4**、JDK **17**、Android SDK **36** 的环境中完成构建；最低 Android 版本为 **7.0 / API 24**。

```powershell
git clone https://github.com/tingwu-h/wanxiang-chat-app.git
cd wanxiang-chat-app
flutter pub get
flutter analyze
flutter test
flutter run
```

运行前准备 Android 模拟器或已开启 USB 调试的 Android 手机，并通过 `flutter doctor` 检查本地环境。

## 主要能力与代码入口

v1.4.x 在最初的多模型流式对话之外，还包含：图片与文本附件、直接拍照、联网搜索（DeepSeek Search / Fetch，可开关）、每会话独立提示词、思考模式与四档强度（No / Low / High / Max）、自动告知当前时间、TXT 导出、气泡文字选取与追问。

| 入口 | 说明 |
| --- | --- |
| `lib/pages/chat_page.dart` | 聊天页、悬浮顶栏、更多菜单、输入窗口、会话导出 |
| `lib/providers/chat_provider.dart` | 会话状态、流式请求、联网编排、提示词拼装、持久化检查点 |
| `lib/services/api_protocol.dart` | 四类协议（OpenAI Chat / Responses / Anthropic / Gemini）的请求与解码 |
| `lib/services/search_service.dart` | DeepSeek 官方 Search / Fetch 封装 |
| `lib/services/storage_service.dart` | 设置与会话持久化、历史导出 |
| `lib/services/platform_service.dart` | 平台通道：安全存储、TXT / JSON 导出、回桌面 |
| `lib/pages/settings_page.dart` | 五分类设置（模型与服务、对话设置、外观设置、数据管理、关于） |
| `lib/pages/model_behaviour_page.dart` | 思考强度滑条、图片档位、时间注入 |
| `lib/pages/search_settings_page.dart` | 联网搜索开关、Key、条数、抓正文、来源显示 |
| `lib/widgets/thinking_level_slider.dart` | 设置页的四档滑条（No / Low / High / Max） |
| `lib/widgets/thinking_level_popover.dart` | 输入栏「思考」胶囊上方的四档悬浮框 |
| `lib/utils/app_localizations.dart` | 简中 / 繁中 / 英文文案；缺 key 时回落简体中文 |

## 维护者离线构建与原签名升级

```powershell
& .\tools\build-release-offline.ps1 -ToolRoot C:\dsbuild
```

该脚本使用维护者已有的 Flutter、JDK、Android SDK 与 Pub / Gradle 缓存，执行依赖解析、静态分析、测试、Release APK 构建和证书校验；不自动安装或上传。产物为 `dist/wanxiang-v1.4.5.apk`。

脚本沿用当前用户 Android 配置目录中的原有 `debug.keystore`，不移动或重建文件，并检查预期证书。签名文件不包含在仓库中；其他开发者自己的签名不能覆盖安装维护者签名的版本。

## 协议与平台扩展结构

<details>
<summary><strong>扩展说明</strong></summary>

- `ChatService`：定义通用聊天能力，供聊天状态层调用。
- [ApiProtocol](../lib/services/api_protocol.dart)：处理不同服务商的请求和响应协议，包括 DeepSeek 的 `thinking.type` 与 `reasoning_effort`。
- [ProviderCatalog](../lib/models/provider_catalog.dart)：维护服务商预置与配置入口。
- [PlatformBackend](../lib/services/platform_service.dart)：隔离安全存储、导出和退出等平台服务。

后续桌面端可以复用聊天与协议逻辑，再实现对应系统的安全存储和文件导出。本版非 Android 的密钥回退仅保存在内存中，不能视为完整桌面支持。

</details>

## 已验证的范围

截至 **2026-11-07**（v1.4.5）：静态分析无问题，**193 项测试通过**，Release APK 构建成功，版本号、包名（`com.example.deepseek_chat`）与原签名一致性已校验。

测试覆盖模拟协议请求、流式响应、多服务商密钥隔离、旧数据迁移、失败分类、联网搜索、思考强度四档与请求体、时间注入、会话导出、气泡交互与多项 UI 回归。**各服务商的真实账号调用与手机覆盖升级尚未实测**，模拟测试通过不代表所有账号和模型均可在线使用。

