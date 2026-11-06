/// Service presets are editable; model availability depends on the user's account.
class ProviderPreset {
  const ProviderPreset(
    this.id,
    this.name,
    this.url,
    this.models,
    this.platform, {
    this.protocol = 'openai',
  });
  final String id, name, url, platform, protocol;
  final List<String> models;
}

const providerCatalog = <ProviderPreset>[
  ProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com', [
    'deepseek-flash',
    'deepseek-v4-pro',
  ], 'https://platform.deepseek.com'),
  ProviderPreset(
    'openai',
    'OpenAI · GPT',
    'https://api.openai.com/v1',
    ['gpt-4.1', 'gpt-4.1-mini'],
    'https://platform.openai.com',
    protocol: 'responses',
  ),
  ProviderPreset('kimi', 'Kimi · Moonshot', 'https://api.moonshot.cn/v1', [
    'kimi-k2.5',
    'moonshot-v1-8k',
  ], 'https://platform.moonshot.cn'),
  ProviderPreset(
    'qwen',
    'Qwen · 通义千问',
    'https://dashscope.aliyuncs.com/compatible-mode/v1',
    ['qwen-plus', 'qwen-turbo', 'qwen-vl-plus'],
    'https://bailian.console.aliyun.com',
  ),
  ProviderPreset(
    'anthropic',
    'Anthropic · Claude',
    'https://api.anthropic.com/v1',
    ['claude-sonnet-4-5', 'claude-haiku-4-5'],
    'https://console.anthropic.com',
    protocol: 'anthropic',
  ),
  ProviderPreset(
    'google',
    'Google · Gemini',
    'https://generativelanguage.googleapis.com/v1beta',
    ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.5-flash-lite'],
    'https://aistudio.google.com/apikey',
    protocol: 'gemini',
  ),
  ProviderPreset('xai', 'xAI · Grok', 'https://api.x.ai/v1', [
    'grok-4',
    'grok-3-mini',
  ], 'https://console.x.ai'),
  ProviderPreset('glm', 'GLM · 智谱', 'https://open.bigmodel.cn/api/paas/v4', [
    'glm-4.7',
    'glm-4.6v',
  ], 'https://open.bigmodel.cn'),
  ProviderPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', [
    'openrouter/free',
    'qwen/qwen3.8-27b:free',
  ], 'https://openrouter.ai/settings/keys'),
  ProviderPreset('custom', '自定义服务商', '', [], ''),
];

ProviderPreset presetFor(String id) => providerCatalog.firstWhere(
  (p) => p.id == id,
  orElse: () => providerCatalog.last,
);

bool modelSupportsImages(String model) => [
  'openrouter/free',
  'qwen/qwen3.8-27b:free',
  'deepseek-flash',
  'deepseek-v4-flash',
  'deepseek-v4-flash-vision-exp',
  'gpt-4.1',
  'gpt-4.1-mini',
  'kimi-k2.5',
  'qwen-vl-plus',
  'claude-sonnet-4-5',
  'claude-haiku-4-5',
  'gemini-2.5-flash',
  'gemini-2.5-pro',
  'gemini-2.5-flash-lite',
  'glm-4.6v',
].contains(model);
