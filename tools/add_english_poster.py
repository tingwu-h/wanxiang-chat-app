"""加入英文横版海报。

中文版海报保持不动（README.zh-CN.md 继续引用中文版），
英文版单独成文件，供 README.md 引用。

用法：把英文海报放到本目录下的 `_new-landscape-en.png`，然后运行本脚本。
"""
from pathlib import Path

from PIL import Image

POSTERS = Path(__file__).resolve().parent.parent / "docs" / "posters"

SRC = POSTERS / "_new-landscape-en.png"
BASE = "wanxiang-poster-landscape-en"
PREVIEW_W = 1920


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"缺少输入文件：{SRC}")

    img = Image.open(SRC)

    png = POSTERS / f"{BASE}.png"
    img.save(png, "PNG", optimize=True)

    # 预览宽度不超过原图宽度，避免放大导致模糊
    preview_w = min(PREVIEW_W, img.width)
    ratio = preview_w / img.width
    preview = img.convert("RGB").resize(
        (preview_w, round(img.height * ratio)), Image.LANCZOS
    )
    preview_path = POSTERS / f"{BASE}-preview.jpg"
    preview.save(preview_path, "JPEG", quality=88, optimize=True, subsampling=0)

    print(f"  {BASE}")
    print(f"     源图    {img.width} x {img.height}")
    print(f"     PNG     {png.stat().st_size / 1024:.0f} KB")
    print(f"     预览    {preview.width} x {preview.height}  "
          f"{preview_path.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
