"""用用户提供的最终海报（二维码已嵌入）替换仓库里的占位版本。

输入：docs/posters/_new-landscape.jpg、_new-portrait.jpg
输出：PNG（README 引用）、JPG（原图备份）、-preview.jpg（网页预览）

不缩放、不重采样，只做格式转换与预览缩放，保证画质不损失。
"""
from pathlib import Path

from PIL import Image

POSTERS = Path(__file__).resolve().parent.parent / "docs" / "posters"

JOBS = [
    # (临时原图, 输出基名, 预览宽度)
    ("_new-landscape.jpg", "wanxiang-poster-landscape", 1920),
    ("_new-portrait.jpg", "wanxiang-poster-portrait", 1080),
]


def main() -> None:
    for src_name, base, preview_w in JOBS:
        src = POSTERS / src_name
        if not src.exists():
            raise SystemExit(f"缺少输入文件：{src}")

        img = Image.open(src)

        # PNG：README 直接引用，保持原始分辨率
        png = POSTERS / f"{base}.png"
        img.save(png, "PNG", optimize=True)

        # JPG：原图备档，高质量
        jpg = POSTERS / f"{base}.jpg"
        img.convert("RGB").save(jpg, "JPEG", quality=92, optimize=True, subsampling=0)

        # 预览：按宽度等比缩小，供网页快速加载
        ratio = preview_w / img.width
        preview = img.convert("RGB").resize(
            (preview_w, round(img.height * ratio)), Image.LANCZOS
        )
        preview_path = POSTERS / f"{base}-preview.jpg"
        preview.save(preview_path, "JPEG", quality=88, optimize=True, subsampling=0)

        print(f"  {base}")
        print(f"     源图      {img.width} x {img.height}")
        print(f"     PNG       {png.stat().st_size / 1024:.0f} KB")
        print(f"     JPG       {jpg.stat().st_size / 1024:.0f} KB")
        print(f"     预览      {preview.width} x {preview.height}  "
              f"{preview_path.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
