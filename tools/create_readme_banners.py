"""Compose bilingual banners from Flutter screenshots. Requires Pillow.

Pass --font with a Chinese-capable TrueType/OpenType font.
"""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--font', default='C:/Windows/Fonts/msyh.ttc')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
version = next(line.split(':', 1)[1].strip().split('+')[0]
               for line in (root / 'pubspec.yaml').read_text(encoding='utf-8').splitlines()
               if line.startswith('version:'))
for language in ['zh', 'en']:
    canvas = Image.new('RGB', (1600, 780))
    pixels = canvas.load()
    for y in range(canvas.height):
        for x in range(canvas.width):
            g = max(0, 1 - ((x - 1210) / 1100) ** 2 - ((y - 180) / 940) ** 2)
            pixels[x, y] = (int(9 + 14 * g), int(16 + 25 * g), int(38 + 46 * g))
    draw = ImageDraw.Draw(canvas)
    def text(x, y, value, size, color):
        draw.text((x, y), value, font=ImageFont.truetype(args.font, size), fill=color)
    icon = Image.open(root / 'assets/branding/icon.png').convert('RGBA').resize((96, 96), Image.Resampling.LANCZOS)
    canvas.paste(icon, (72, 70), icon)
    text(196, 66, '万象' if language == 'zh' else 'Wanxiang', 48, '#FFFFFF')
    text(198, 132, f'AI CHAT FOR ANDROID  /  v{version}', 17, '#9DB5D5')
    if language == 'zh':
        text(72, 234, '万象聚合', 66, '#FFFFFF')
        text(72, 326, '模型无界', 66, '#59DEF4')
        text(76, 462, '多种 AI，一个入口。', 30, '#D1DCF0')
        text(76, 515, '让灵感流动，让对话更自在。', 25, '#A7BAD7')
        pills = [('Android', 136), ('禁止商用', 156), ('自备 API Key', 194)]
    else:
        text(72, 242, 'More models.', 58, '#FFFFFF')
        text(72, 330, 'Fewer boundaries.', 58, '#59DEF4')
        text(76, 466, 'Your models. One app.', 29, '#D1DCF0')
        text(76, 518, 'Space to think. Room to explore.', 24, '#A7BAD7')
        pills = [('Android', 136), ('Non-commercial', 232), ('Your API key', 192)]
    x = 76
    for label, width in pills:
        draw.rounded_rectangle((x, 608, x + width, 654), radius=23, fill='#203352', outline='#375476')
        text(x + 18, 618, label, 19, '#D6E9FF')
        x += width + 16
    suffix = '-en' if language == 'en' else ''
    for name, x, y, width in [('chat-dark', 1230, 118, 265), ('chat-light', 920, 65, 280)]:
        shot = Image.open(root / f'docs/screenshots/{name}{suffix}.png').convert('RGB')
        height = round(shot.height * width / shot.width)
        shot = shot.resize((width, height), Image.Resampling.LANCZOS)
        draw.rounded_rectangle((x - 8, y - 8, x + width + 8, y + height + 8), radius=28, fill='#14233E', outline='#446082', width=2)
        mask = Image.new('L', shot.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=20, fill=255)
        canvas.paste(shot, (x, y), mask)
    text(76, 727, 'DeepSeek  /  OpenAI  /  Kimi  /  Qwen  /  Claude  /  Gemini  /  Grok  /  GLM  /  OpenRouter', 18, '#91AACE')
    output = root / f'docs/images/wanxiang-banner{suffix}.png'
    canvas.save(output, optimize=True)
    print(output)
