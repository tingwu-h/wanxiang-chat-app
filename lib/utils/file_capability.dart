/// 哪些服务商已适配文档生成。
///
/// v1.6.0 只打通 DeepSeek；其它服务商在模型菜单与创建入口里显示“暂不支持”。
bool supportsFileGeneration(String providerId) => providerId == 'deepseek';
