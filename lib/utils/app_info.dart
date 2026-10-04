/// 应用版本号。
///
/// 这个常量由构建脚本 tools/ascii_build.ps1 在编译前**改写成本次版本号**
/// （从构建副本的 pubspec.yaml 取），保证界面显示的版本永远和发出去的包一致。
///
/// 为什么不用 --dart-define + String.fromEnvironment：
/// 注入的值在 AOT 产物里取不到（实测），装到手机上会显示成兜底文案。
/// 直接写成源码里的 const 是编译期字面量，最可靠。
///
/// 这个值是对外显示的 Android 热修复版本；Dart pubspec 保留三段基础版本，
/// 构建脚本和 Android Gradle 配置会将完整热修复版本写入 APK。
const String kAppVersion = '1.3.1';

/// 创作者（显示在「关于」页）
///
/// 要改成你自己的名字/昵称，改这一行即可。
const String kAppAuthor = 'tingwu-h';

/// 创作者的 GitHub 主页（关于页里点「创作者」会跳到这里）
const String kAuthorGithubUrl = 'https://github.com/tingwu-h';

/// 创作者的 GitHub App scheme。
///
/// 装了 GitHub App 时会直接进 App，没装则回退到 [kAuthorGithubUrl] 网页版。
const String kAuthorGithubScheme = 'github://github.com/tingwu-h';

/// DeepSeek 开放平台地址（申请 API Key、充值、查用量）
const String kDeepSeekPlatformUrl = 'https://platform.deepseek.com';

/// API 文档地址
const String kDeepSeekDocsUrl = 'https://api-docs.deepseek.com';

/// 项目源码地址
const String kProjectRepoUrl = 'https://github.com/tingwu-h/wanxiang-chat-app';
