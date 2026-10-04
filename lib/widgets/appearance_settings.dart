import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:deepseek_chat/models/app_settings.dart';
import 'package:deepseek_chat/providers/app_settings_provider.dart';
import 'package:deepseek_chat/pages/image_editor_page.dart';
import 'package:deepseek_chat/services/attachment_service.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key, required this.onSaved});
  final ValueChanged<AppSettings> onSaved;
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool _busy = false;
  bool _choosingLanguage = false;
  static const _languages = {'zh_CN': '简体中文', 'zh_TW': '繁體中文', 'en': 'English'};

  Future<void> _chooseLanguage() async {
    if (_busy || _choosingLanguage) return;
    _choosingLanguage = true;
    FocusScope.of(context).unfocus();
    final current = context.read<AppSettingsProvider>().settings.language;
    final route = ModalBottomSheetRoute<String>(
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Material(
            color: Theme.of(ctx).colorScheme.surfaceContainer,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(
                      t('语言', '語言', 'Language'),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  for (final entry in _languages.entries)
                    ListTile(
                      key: ValueKey('language-option-${entry.key}'),
                      selected: current == entry.key,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Text(entry.value),
                      trailing: current == entry.key
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(ctx, entry.key),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      final selected = await Navigator.of(context).push(route);
      // Finish dismissal before changing the locale and rebuilding the page.
      await route.completed;
      if (mounted && selected != null && selected != current) {
        await _save(language: selected);
      }
    } finally {
      _choosingLanguage = false;
    }
  }

  String t(String cn, String tw, String en) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'en'
        ? en
        : locale.countryCode == 'TW'
        ? tw
        : cn;
  }

  Future<void> _save({String? language, String? color, String? image}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final provider = context.read<AppSettingsProvider>();
    final previousImage = provider.settings.chatBackgroundImage;
    try {
      await provider.updateAppearance(
        language: language,
        color: color,
        image: image,
      );
      widget.onSaved(provider.settings);
      if (image != null && previousImage != image && previousImage.isNotEmpty) {
        // Saved appearance is authoritative even if old-file cleanup fails.
        try {
          await AttachmentService.removeOwnedFile(previousImage);
        } catch (_) {}
      }
    } catch (_) {
      if (image != null && image != previousImage && image.isNotEmpty) {
        try {
          await AttachmentService.removeOwnedFile(image);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('未能保存，请重试', '未能儲存，請重試', 'Could not save. Please retry.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? edited;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      edited = await ImageEditorPage.open(context, file.path, background: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '无法选择图片，请重试',
                '無法選擇圖片，請重試',
                'Could not select an image. Please retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (edited == null) return;
    if (!mounted) {
      await AttachmentService.removeOwnedFile(edited.path);
      return;
    }
    await _save(image: edited.path);
  }

  Future<void> _customColor() async {
    final controller = TextEditingController();
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(t('自定义背景颜色', '自訂背景顏色', 'Custom background color')),
          content: TextField(
            controller: controller,
            maxLength: 7,
            decoration: InputDecoration(hintText: '#E8F0FE', errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('取消', '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final hex = controller.text.trim().replaceFirst('#', '');
                if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
                  update(
                    () => error = t(
                      '请输入 6 位颜色值',
                      '請輸入 6 位顏色值',
                      'Enter a six-digit color',
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, 'ff$hex');
              },
              child: Text(t('使用', '使用', 'Use')),
            ),
          ],
        ),
      ),
    );
    // Dialog exit transitions may still use the controller in this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value != null && mounted) await _save(color: value);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>().settings;
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          ListTile(
            key: const ValueKey('language-setting'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(t('语言', '語言', 'Language')),
            subtitle: Text(_languages[settings.language] ?? '简体中文'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : _chooseLanguage,
          ),
          const SizedBox(height: 16),
          Text(t('聊天背景颜色', '聊天背景顏色', 'Chat background color')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final choice in [
                ('', t('默认', '預設', 'Default')),
                ('fff0f4fa', t('雾蓝', '霧藍', 'Mist')),
                ('ffedf5ed', t('浅绿', '淺綠', 'Sage')),
                ('fffff2e7', t('暖杏', '暖杏', 'Apricot')),
                ('ff202734', t('深蓝', '深藍', 'Navy')),
              ])
                ChoiceChip(
                  label: Text(choice.$2),
                  avatar: choice.$1.isEmpty
                      ? null
                      : CircleAvatar(
                          backgroundColor: Color(
                            int.parse(choice.$1, radix: 16),
                          ),
                        ),
                  selected: settings.chatBackgroundColor == choice.$1,
                  onSelected: (_) => _save(color: choice.$1),
                ),
              ActionChip(
                label: Text(t('自定义', '自訂', 'Custom')),
                onPressed: _customColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wallpaper),
            title: Text(t('上传背景图片', '上傳背景圖片', 'Upload background image')),
            subtitle: Text(
              t(
                '支持裁剪、缩放与自动压缩',
                '支援裁剪、縮放與自動壓縮',
                'Crop, zoom and automatic compression',
              ),
            ),
            onTap: _pick,
          ),
          if (settings.chatBackgroundImage.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(settings.chatBackgroundImage),
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  t('背景图片无法读取', '背景圖片無法讀取', 'Background image unavailable'),
                ),
              ),
            ),
            TextButton(
              onPressed: () => _save(image: ''),
              child: Text(t('移除背景图片', '移除背景圖片', 'Remove background image')),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
