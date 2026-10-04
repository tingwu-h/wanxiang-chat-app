# 万象长期宣传海报

主标语：万象聚合，模型无界。

辅助文案：让每个想法，都有回响。把常用的 AI 放在一起，让对话更自在。

设计要求：沿用项目所有者提供的 Logo；深蓝底与宽范围、低对比的蓝紫渐变；清晰的中文排版；不含版本号、日期、服务商数量、具体模型列表或可能过时的 UI 截图。右下角为项目主页二维码。

当前版本：由项目所有者提供的最终稿，**二维码已嵌入**，分辨率高于早期排版稿。

文件：

- `wanxiang-poster-portrait.png` / `.jpg`：1773 × 2364 竖版。
- `wanxiang-poster-landscape.png` / `.jpg`：2730 × 1536 横版。
- `*-preview.jpg`：缩小预览，不用于替代原图。

二维码位于右下角，约占画面宽度 4%，四周保留白色静区。需要重排版时按比例定位，不要沿用早期 1440 × 1920 / 1920 × 1080 版本记录的绝对像素坐标。

制作方式：原品牌位图合成 + Pillow 中文字体精确排版，没有使用内置生图工具或图像 API；文案和布局参数在 `tools/create_poster.py`。可在具备 Pillow、NumPy 及 Windows 微软雅黑字体的环境运行 `python tools/create_poster.py` 重新生成。品牌原资源未修改。

替换最终稿时把横竖两张按 `_new-landscape.jpg` / `_new-portrait.jpg` 放进本目录，运行 `python tools/replace_posters.py`，会同时更新 PNG、JPG 和预览图。
