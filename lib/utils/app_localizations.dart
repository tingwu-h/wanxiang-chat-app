import 'package:flutter/widgets.dart';

String localized(BuildContext context, String cn, String tw, String en) {
  final locale = Localizations.localeOf(context);
  return locale.languageCode == 'en'
      ? en
      : locale.countryCode == 'TW'
      ? tw
      : cn;
}

/// Application labels; model replies, IDs and user-created titles stay intact.
String tr(
  BuildContext context,
  String source, [
  Map<String, Object> values = const {},
]) {
  final locale = Localizations.localeOf(context);
  final pair = _labels[source];
  var result = pair == null || locale.countryCode == 'CN'
      ? source
      : locale.languageCode == 'en'
      ? pair.$2
      : pair.$1;
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

const _labels = <String, (String, String)>{
  '多模型聚合': ('多模型聚合', 'Model aggregation'),
  '免费模型入口': ('免費模型入口', 'Free model access'),
  '版本 v{version}': ('版本 v{version}', 'Version v{version}'),
  '回答发散度  {value}': ('回答發散度  {value}', 'Creativity  {value}'),
  '当前模型：{model}': ('目前模型：{model}', 'Current model: {model}'),
  '已切换到 {model}': ('已切換至 {model}', 'Switched to {model}'),
  '思考过程（点击收起）': ('思考過程（點擊收合）', 'Reasoning (tap to collapse)'),
  '思考过程（{count} 字，点击展开）': (
    '思考過程（{count} 字，點擊展開）',
    'Reasoning ({count} characters, tap to expand)',
  ),
  '「{title}」将被永久删除。': (
    '「{title}」將被永久刪除。',
    '“{title}” will be permanently deleted.',
  ),
  '{count} 条': ('{count} 則', '{count} chats'),
  '图片已不在本地': ('圖片已不在本機', 'Image is no longer on this device'),
  '恢复默认设置？': ('恢復預設設定？', 'Reset settings?'),
  '将清空已保存的 API Key、系统提示词等全部配置。': (
    '將清除已儲存的 API Key、系統提示詞等全部設定。',
    'This clears API Keys, system prompts and all other settings.',
  ),
  '恢复': ('恢復', 'Reset'),
  '已恢复默认设置': ('已恢復預設設定', 'Settings reset'),
  '恢复失败，请重试': ('恢復失敗，請重試', 'Could not reset. Please retry.'),
  '确认清空': ('確認清空', 'Confirm'),
  '聊天记录和不再使用的图片将被删除，无法撤销。建议先导出重要内容。': (
    '聊天紀錄及不再使用的圖片將被刪除，無法復原。建議先匯出重要內容。',
    'Chats and unused attachments will be deleted permanently. Export important content first.',
  ),
  '已清空全部对话': ('已清空全部對話', 'All chats cleared'),
  '清理失败，请重试': ('清理失敗，請重試', 'Could not clear chats. Please retry.'),
  '设置帮助': ('設定說明', 'Settings help'),
  '展开分类进行修改，完成后点击保存。主题选择后立即生效。测试连接会产生真实 API 用量，但不会自动保存配置。': (
    '展開分類修改後點擊儲存。外觀選擇立即生效。測試連線會產生 API 用量，但不會儲存設定。',
    'Expand a category, edit and save. Appearance changes apply immediately. Connection tests use API quota and do not save settings.',
  ),
  '有未保存的修改': ('有未儲存的修改', 'Unsaved changes'),
  '待配置': ('待設定', 'Not configured'),
  '已填写密钥': ('已填寫金鑰', 'Key entered'),
  '显示': ('顯示', 'Show'),
  '隐藏': ('隱藏', 'Hide'),
  '向你的接口服务商申请密钥，复制后回到这里粘贴。': (
    '向你的服務商申請金鑰，複製後返回此處貼上。',
    'Get an API Key from your provider, then return here and paste it.',
  ),
  '接口地址格式不正确，请检查后再试。': (
    '介面位址格式不正確，請檢查後重試。',
    'Invalid API endpoint. Please check and retry.',
  ),
  '连接失败，请检查网络和配置': (
    '連線失敗，請檢查網路與設定',
    'Connection failed. Check your network and settings.',
  ),
  '连接成功：{reply}': ('連線成功：{reply}', 'Connected: {reply}'),
  '聊天文字已导出，图片文件不包含在内。': (
    '聊天文字已匯出，不包含圖片檔案。',
    'Chat text exported. Image files are not included.',
  ),
  '导出失败，请重新选择保存位置。': (
    '匯出失敗，請重新選擇儲存位置。',
    'Export failed. Choose another save location.',
  ),
  '这个对话包含图片，请切换到支持图片的模型，并在设置中确认图片能力。': (
    '此對話包含圖片，請切換至支援圖片的模型並確認圖片設定。',
    'This chat contains images. Choose a model that accepts images and enable image input.',
  ),
  '选择图片失败，请重试': ('選擇圖片失敗，請重試', 'Could not select images. Please retry.'),
  '选择文件失败，请重试': ('選擇檔案失敗，請重試', 'Could not select files. Please retry.'),
  '部分临时图片未能清理，请稍后重试。': (
    '部分暫存圖片未能清理，請稍後重試。',
    'Some temporary images could not be removed. Please retry later.',
  ),
  '日常问答': ('日常問答', 'Everyday Q&A'),
  '快速回复': ('快速回覆', 'Fast replies'),
  '复杂推理': ('複雜推理', 'Reasoning'),
  '编程': ('程式設計', 'Coding'),
  '写作': ('寫作', 'Writing'),
  '数学': ('數學', 'Math'),
  '长文': ('長文', 'Long text'),
  '图片理解': ('圖片理解', 'Vision'),
  '图文问答': ('圖文問答', 'Visual Q&A'),
  '免费额度': ('免費額度', 'Free quota'),
  '自动选模': ('自動選模', 'Auto-select'),
  '限额免费': ('限額免費', 'Free with limits'),
  '能力待确认': ('能力待確認', 'Check capabilities'),
  '需 Google API Key。免费层有额度和地区限制，付费层按量计费；免费层内容可能用于改进产品。': (
    '需 Google API Key。免費層有額度及地區限制；付費層按用量計費；免費層內容可能用於改進產品。',
    'Requires a Google API Key. Free tier has quota and region limits; paid tier is metered. Free tier content may be used to improve products.',
  ),
  '需 OpenRouter API Key。自动选择可用的免费模型，能力和可用性可能变化；有请求限额。': (
    '需 OpenRouter API Key。自動選擇可用的免費模型；能力及可用性可能改變，有請求限額。',
    'Requires an OpenRouter API Key. Automatically selects available free models; capabilities and availability vary. Request limits apply.',
  ),
  '需 OpenRouter API Key。使用免费变体，有请求限额；供应商可用性以平台为准。': (
    '需 OpenRouter API Key。使用免費版本，有請求限額；可用性以平台為準。',
    'Requires an OpenRouter API Key. Free variant with request limits; availability depends on the platform.',
  ),
  '万象': ('萬象', 'Wanxiang'),
  '万象聚合，模型无界': ('萬象聚合，模型無界', 'Wanxiang aggregation, limitless models'),
  '设置': ('設定', 'Settings'),
  '关于': ('關於', 'About'),
  '关于万象': ('關於萬象', 'About Wanxiang'),
  '模型与服务': ('模型與服務', 'Models & providers'),
  '对话设置': ('對話設定', 'Chat settings'),
  '回复风格与图片': ('回覆風格與圖片', 'Response style and images'),
  '外观设置': ('外觀設定', 'Appearance'),
  '数据管理': ('資料管理', 'Data'),
  '导出、清理与重置': ('匯出、清理與重設', 'Export, clear and reset'),
  '跟随系统': ('跟隨系統', 'System'),
  '浅色': ('淺色', 'Light'),
  '深色': ('深色', 'Dark'),
  '主题立即生效': ('主題立即生效', 'Appearance changes apply immediately'),
  '历史对话': ('歷史對話', 'Chat history'),
  '新对话': ('新對話', 'New chat'),
  '新建对话': ('新增對話', 'New chat'),
  '清空当前对话': ('清空目前對話', 'Clear current chat'),
  '清空当前对话？': ('清空目前對話？', 'Clear this chat?'),
  '这个对话里的消息会被删除，此操作无法撤销。': (
    '此對話的訊息將被刪除，無法復原。',
    'Messages in this chat will be deleted. This cannot be undone.',
  ),
  '已清空当前对话': ('已清空目前對話', 'Chat cleared'),
  '清空全部对话': ('清空全部對話', 'Clear all chats'),
  '清空全部对话？': ('清空全部對話？', 'Clear all chats?'),
  '所有历史对话都会被删除，此操作无法撤销。': (
    '所有歷史對話將被刪除，無法復原。',
    'All chats will be deleted. This cannot be undone.',
  ),
  '还没有历史对话': ('尚無歷史對話', 'No chat history yet'),
  '对话操作': ('對話操作', 'Chat actions'),
  '切换模型': ('切換模型', 'Switch model'),
  '更多': ('更多', 'More'),
  '重命名': ('重新命名', 'Rename'),
  '重命名对话': ('重新命名對話', 'Rename chat'),
  '删除': ('刪除', 'Delete'),
  '删除这个对话？': ('刪除此對話？', 'Delete this chat?'),
  '取消': ('取消', 'Cancel'),
  '清空': ('清空', 'Clear'),
  '确定': ('確定', 'OK'),
  '知道了': ('知道了', 'Got it'),
  '保存': ('儲存', 'Save'),
  '正在保存…': ('正在儲存…', 'Saving…'),
  '保存修改？': ('儲存修改？', 'Save changes?'),
  '还有未保存的设置。': ('還有未儲存的設定。', 'You have unsaved settings.'),
  '继续编辑': ('繼續編輯', 'Keep editing'),
  '放弃修改': ('放棄修改', 'Discard'),
  '保存并返回': ('儲存並返回', 'Save and return'),
  '给这个对话起个名字': ('為此對話命名', 'Name this chat'),
  '留空则恢复为自动标题': ('留空則恢復自動標題', 'Leave empty to use an automatic title'),
  '正在回复…': ('正在回覆…', 'Replying…'),
  '给万象发消息…': ('傳送訊息給萬象…', 'Message Wanxiang…'),
  '请先在设置里填写 API Key': ('請先在設定中填寫 API Key', 'Add an API Key in Settings first'),
  '添加图片或文件': ('新增圖片或檔案', 'Add images or files'),
  '图片': ('圖片', 'Images'),
  '文件': ('檔案', 'Files'),
  'txt / md / json / csv / 代码': (
    'txt / md / json / csv / 程式碼',
    'txt / md / json / csv / code',
  ),
  '停止生成': ('停止生成', 'Stop generating'),
  '发送': ('傳送', 'Send'),
  '我': ('我', 'You'),
  '正在生成回答': ('正在生成回覆', 'Generating response'),
  '已复制这条消息': ('已複製此訊息', 'Message copied'),
  '复制': ('複製', 'Copy'),
  '粘贴': ('貼上', 'Paste'),
  '再按一次回到桌面': ('再按一次返回桌面', 'Press back again to return home'),
  '请先配置所选服务商的 API Key': (
    '請先設定所選服務商的 API Key',
    'Set an API Key for this provider first',
  ),
  '去设置': ('前往設定', 'Settings'),
  '配置未能保存，请重试': ('設定未能儲存，請重試', 'Could not save settings. Please retry.'),
  '配置模型服务商': ('設定模型服務商', 'Set up a provider'),
  '还没配置 API Key，从左侧抽屉进入「设置」填写。': (
    '尚未設定 API Key，請從左側選單進入「設定」填寫。',
    'Add your API Key in Settings from the left menu.',
  ),
  '服务商': ('服務商', 'Provider'),
  '模型': ('模型', 'Model'),
  '自定义模型': ('自訂模型', 'Custom model'),
  '模型 ID': ('模型 ID', 'Model ID'),
  '填写服务商提供的模型 ID': ('填寫服務商提供的模型 ID', 'Enter the model ID from your provider'),
  '获取 API Key': ('取得 API Key', 'Get an API Key'),
  '申请步骤': ('申請步驟', 'How to get a key'),
  '如何获取 API Key': ('如何取得 API Key', 'How to get an API Key'),
  '查看免费额度说明': ('查看免費額度說明', 'View free quota details'),
  '高级设置': ('進階設定', 'Advanced'),
  '接口地址与协议': ('介面位址與協定', 'Endpoint and protocol'),
  '接口地址': ('介面位址', 'API endpoint'),
  '接口协议': ('介面協定', 'API protocol'),
  'OpenAI 兼容': ('OpenAI 相容', 'OpenAI compatible'),
  '测试连接': ('測試連線', 'Test connection'),
  '正在测试…': ('正在測試…', 'Testing…'),
  '会产生 API 用量；测试不会自动保存。': (
    '會產生 API 用量；測試不會自動儲存。',
    'Uses API quota. Testing does not save settings.',
  ),
  '系统提示词': ('系統提示詞', 'System prompt'),
  '例如：回答简洁，优先使用中文': (
    '例如：回答簡潔，優先使用繁體中文',
    'Example: Be concise and answer in English',
  ),
  '更稳定': ('更穩定', 'More consistent'),
  '更多变化': ('更多變化', 'More varied'),
  '允许发送图片': ('允許傳送圖片', 'Allow image input'),
  '图片能力': ('圖片能力', 'Image support'),
  '如何选择？': ('如何選擇？', 'How to choose?'),
  '仅对支持图片的模型开启。自定义模型的能力以服务商说明为准。': (
    '僅對支援圖片的模型開啟。自訂模型的能力以服務商說明為準。',
    'Enable only for models that accept images. Check your provider for custom models.',
  ),
  '导出聊天文字': ('匯出聊天文字', 'Export chat text'),
  '正在导出…': ('正在匯出…', 'Exporting…'),
  '不含密钥和图片文件': ('不含金鑰和圖片檔案', 'Excludes keys and image files'),
  '恢复默认设置': ('恢復預設設定', 'Reset settings'),
  '清除配置，保留聊天记录': ('清除設定，保留聊天紀錄', 'Reset configuration and keep chats'),
  '项目主页': ('專案首頁', 'Project home'),
  '项目源码': ('專案原始碼', 'Source code'),
  '使用许可': ('使用授權', 'License'),
  '源码公开，禁止商用': ('原始碼公開，禁止商用', 'Source available, non-commercial use only'),
  '万象非商业使用许可证': ('萬象非商業使用授權', 'Wanxiang non-commercial license'),
  '创作者': ('創作者', 'Creator'),
  '选择免费模型': ('選擇免費模型', 'Choose a free model'),
  '需自己的 API Key，额度以官方平台为准': (
    '需自己的 API Key，額度以官方平台為準',
    'Bring your own API Key. Quotas are set by the provider.',
  ),
  '免费模型自动选择': ('免費模型自動選擇', 'Automatic free model'),
  'Qwen 3.8 27B · 免费变体': ('Qwen 3.8 27B · 免費版本', 'Qwen 3.8 27B · Free variant'),
  'Gemini Flash-Lite · 免费额度': (
    'Gemini Flash-Lite · 免費額度',
    'Gemini Flash-Lite · Free quota',
  ),
  '设置已保存': ('設定已儲存', 'Settings saved'),
  '保存失败，请重试': ('儲存失敗，請重試', 'Could not save. Please retry.'),
  '主题未能保存，请重试': ('主題未能儲存，請重試', 'Could not save theme. Please retry.'),
  '请填写有效的接口地址': ('請填寫有效的介面位址', 'Enter a valid API endpoint'),
  '请选择或填写模型': ('請選擇或填寫模型', 'Select or enter a model'),
  '请先填写 API Key': ('請先填寫 API Key', 'Enter an API Key first'),
  '请检查「模型与服务」中的提示': ('請檢查「模型與服務」中的提示', 'Check the hints in Models & providers'),
  '确认接口接收方': ('確認介面接收方', 'Confirm API destination'),
  '返回检查': ('返回檢查', 'Go back'),
  '确认使用': ('確認使用', 'Confirm'),
  '（空回复）': ('（空回覆）', '(Empty reply)'),
  '已取消导出': ('已取消匯出', 'Export cancelled'),
};
