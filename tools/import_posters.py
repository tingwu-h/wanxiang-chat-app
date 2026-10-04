"""替换或新增万象宣传海报。

把新图按下面的约定命名放进 `docs/posters/`，然后运行本脚本；
脚本会生成 README 引用的 PNG 和网页预览 JPG。

约定文件名（png/jpg 均可）：

- `_new-landscape.png`     中文横版 -> `wanxiang-poster-landscape.*`
- `_new-portrait.png`      中文竖版 -> `wanxiang-poster-portrait.*`
- `_new-landscape-en.png`  英文横版 -> `wanxiang-poster-landscape-en.*`

只处理实际存在的输入文件，其余不动。

已知问题：在 Windows 上，脚本有时无法删除处理完的 `_new-*` 临时原图
（WinError 5 拒绝访问，通常是杀毒软件正在扫描刚写入的图片）。
脚本会重试几次，仍失败时只是打印提示，不影响已生成的结果；
换个进程手动删除即可。

用法：
    python tools/import_posters.py
"""
from pathlib import Path
import time

from PIL import Image

POSTERS = Path(__file__).resolve().parent.parent / "docs" / "posters"

# 输入文件名 -> (输出基名, 是否额外输出高质量 JPG 备档, 预览宽度上限)
JOBS = {
    "_new-landscape.png": ("wanxiang-poster-landscape", True, 1920),
    "_new-landscape.jpg": ("wanxiang-poster-landscape", True, 1920),
    "_new-portrait.png": ("wanxiang-poster-portrait", True, 1080),
    "_new-portrait.jpg": ("wanxiang-poster-portrait", True, 1080),
    "_new-landscape-en.png": ("wanxiang-poster-landscape-en", False, 1920),
    "_new-landscape-en.jpg": ("wanxiang-poster-landscape-en", False, 1920),
    "_new-portrait-en.png": ("wanxiang-poster-landscape-en", False, 1080),
}


def process(src: Path, base: str, keep_jpg: bool, preview_cap: int) -> None:
    # 句柄必须全部关闭：Image.open 惰性打开，convert()/resize() 又会产生新的
    # 图片对象各自持有句柄；只要有一个没关，后面删源文件时在 Windows 上就会
    # 抛 PermissionError（WinError 5）。这里逐个用 with 包住。
    with Image.open(src) as img:
        img.load()

        png = POSTERS / f"{base}.png"
        img.save(png, "PNG", optimize=True)
        print(f"  {base}")
        print(f"     源图    {img.width} x {img.height}")
        print(f"     PNG     {png.stat().st_size / 1024:.0f} KB")

        if keep_jpg:
            jpg = POSTERS / f"{base}.jpg"
            with img.convert("RGB") as rgb:
                rgb.save(jpg, "JPEG", quality=92, optimize=True, subsampling=0)
            print(f"     JPG     {jpg.stat().st_size / 1024:.0f} KB")

        # 预览宽度不超过原图宽度，避免放大反而变模糊
        preview_w = min(preview_cap, img.width)
        ratio = preview_w / img.width
        preview_path = POSTERS / f"{base}-preview.jpg"
        with img.convert("RGB") as rgb:
            with rgb.resize(
                (preview_w, round(img.height * ratio)), Image.LANCZOS
            ) as preview:
                preview.save(
                    preview_path, "JPEG", quality=88, optimize=True, subsampling=0
                )
                print(f"     预览    {preview.width} x {preview.height}  "
                      f"{preview_path.stat().st_size / 1024:.0f} KB")


def remove_with_retry(path: Path, attempts: int = 5) -> bool:
    """删除文件，失败就稍等重试。

    Windows 上刚写完的图片可能正被杀毒软件扫描，此时 unlink 会抛
    PermissionError（WinError 5）。这种锁是瞬时的，重试即可；
    实在删不掉也不算失败——输出文件已经生成好了。
    """
    for i in range(attempts):
        try:
            path.unlink()
            return True
        except PermissionError:
            time.sleep(0.4 * (i + 1))
        except OSError:
            time.sleep(0.4 * (i + 1))
    return False


def main() -> None:
    handled = 0
    leftovers: list[str] = []
    for name, (base, keep_jpg, cap) in JOBS.items():
        src = POSTERS / name
        if src.exists():
            process(src, base, keep_jpg, cap)
            if not remove_with_retry(src):
                leftovers.append(name)
            handled += 1

    if handled == 0:
        raise SystemExit(
            "没有找到任何 _new-*.png / _new-*.jpg 输入文件。\n"
            "请按脚本开头的约定命名后放入 docs/posters/。"
        )
    print(f"\n  完成，处理了 {handled} 张。")
    if leftovers:
        print(f"  注意：这些临时原图没能自动删除，请手动删除：{', '.join(leftovers)}")


if __name__ == "__main__":
    main()
