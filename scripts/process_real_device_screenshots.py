#!/usr/bin/env python3
"""
Real-Device App Store Screenshot Processor for PDFview
Takes raw iPhone screenshots taken from real devices (via TestFlight),
and converts them into Apple App Store required pixel dimensions:
- iPhone 6.7" Display: 1290 x 2796 (iPhone 15 Pro Max, 14 Pro Max)
- iPhone 6.9" Display: 1320 x 2868 (iPhone 16 Pro Max)
- Framed Marketing Cards (with promotional headers)
"""

import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

INPUT_DIR = Path("AppStoreAssets/RealDeviceScreenshots_Input")
OUTPUT_DIR = Path("AppStoreAssets/Screenshots_ReadyForUpload")

TARGET_SIZES = {
    "iphone_6.7": (1290, 2796),
    "iphone_6.9": (1320, 2868),
}

MARKETING_TITLES = [
    {
        "tag": "大文件·重排·小屏幕",
        "title": "大字畅读 PDF · 重现经典排版",
        "subtitle": "毫秒级本地图形切片与矢量流式重排，告别眯眼与频繁缩放",
        "gradient": ((245, 248, 255), (228, 237, 252)),
        "accent": (41, 108, 255),
    },
    {
        "tag": "手机拍摄切边纠偏",
        "title": "四角自由拉伸 · 告别倾斜阴影",
        "subtitle": "高精度透视纠偏与杂乱黑边切除，纸质书拍照秒变平整电子书",
        "gradient": ((250, 246, 255), (238, 230, 252)),
        "accent": (142, 68, 237),
    },
    {
        "tag": "竖排古籍善本重构",
        "title": "古籍竖排流式化 · 智能逆序重构",
        "subtitle": "专设一键直排，由右至左手势自适应顺滑翻页，畅读线装善本",
        "gradient": ((255, 249, 242), (252, 237, 222)),
        "accent": (224, 102, 36),
    },
    {
        "tag": "四色护眼纸张",
        "title": "温润纸张底色 · 5档舒适排版",
        "subtitle": "羊皮护眼、豆沙绿意与夜间暗黑主题，集成 Apple 离线双语对照翻译",
        "gradient": ((243, 250, 245), (225, 242, 230)),
        "accent": (46, 139, 87),
    },
    {
        "tag": "轻量 iCloud 同步",
        "title": "跨设备接力阅读 · 进度实时共享",
        "subtitle": "不上传占用大文件空间，书名自动匹配，iPhone、iPad 与 Mac 进度互通",
        "gradient": ((242, 249, 255), (220, 238, 255)),
        "accent": (0, 122, 255),
    },
]

def find_font(size: int, bold: bool = False):
    candidates = [
        "/System/Library/Fonts/STHeiti Medium.ttc" if bold else "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/Library/Fonts/PingFang.ttc",
    ]
    for c in candidates:
        if os.path.exists(c):
            try:
                return ImageFont.truetype(c, size)
            except Exception:
                pass
    return ImageFont.load_default()

def draw_gradient(draw, size, top_col, bot_col):
    width, height = size
    r1, g1, b1 = top_col
    r2, g2, b2 = bot_col
    for y in range(height):
        factor = y / height
        draw.line([(0, y), (width, y)], fill=(
            int(r1 + (r2 - r1) * factor),
            int(g1 + (g2 - g1) * factor),
            int(b1 + (b2 - b1) * factor)
        ))

def process_screenshots():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    INPUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Look for raw screenshots
    extensions = {".png", ".jpg", ".jpeg", ".heic"}
    raw_files = sorted([
        f for f in INPUT_DIR.iterdir()
        if f.suffix.lower() in extensions and not f.name.startswith(".")
    ])

    if not raw_files:
        print(f"提示: 未在 '{INPUT_DIR}' 中发现真机截图。")
        print("请用 iPhone 打开 TestFlight 版本的 PDFview，截取 3~5 张图并通过隔空投送 (AirDrop) 存入该文件夹。")
        return

    print(f"发现 {len(raw_files)} 张真机截图，开始按 App Store 规范批量处理...")

    for idx, file_path in enumerate(raw_files):
        try:
            im = Image.open(file_path).convert("RGB")
        except Exception as e:
            print(f"跳过无法打开的文件 {file_path.name}: {e}")
            continue

        meta = MARKETING_TITLES[idx % len(MARKETING_TITLES)]

        # Generate exact full-screen versions for 6.7" and 6.9"
        for size_name, (tw, th) in TARGET_SIZES.items():
            # 1. Pure Fullscreen Device Screenshot (直接全屏裁切至精准像素)
            fullscreen_img = im.resize((tw, th), Image.Resampling.LANCZOS)
            fs_dir = OUTPUT_DIR / f"{size_name}_fullscreen"
            fs_dir.mkdir(parents=True, exist_ok=True)
            fs_out = fs_dir / f"{idx+1:02d}_{file_path.stem}.png"
            fullscreen_img.save(fs_out, "PNG")

            # 2. Framed Marketing Card (带顶部卖点文案与手机圆角阴影)
            card = Image.new("RGB", (tw, th), (255, 255, 255))
            draw = ImageDraw.Draw(card)
            scale = tw / 1290.0

            # Background Gradient
            draw_gradient(draw, (tw, th), meta["gradient"][0], meta["gradient"][1])

            # Header Text
            tag_font = find_font(int(32 * scale), bold=True)
            title_font = find_font(int(58 * scale), bold=True)
            sub_font = find_font(int(34 * scale), bold=False)

            # Tag pill
            pad_top = int(140 * scale)
            tag_bbox = draw.textbbox((0, 0), meta["tag"], font=tag_font)
            tag_w = tag_bbox[2] - tag_bbox[0]
            tag_h = tag_bbox[3] - tag_bbox[1]
            pill_w = tag_w + int(48 * scale)
            pill_h = tag_h + int(20 * scale)
            pill_x = (tw - pill_w) // 2
            pill_y = pad_top

            pill_bg = Image.new("RGBA", (pill_w, pill_h), (0, 0, 0, 0))
            pill_draw = ImageDraw.Draw(pill_bg)
            accent = meta["accent"]
            pill_draw.rounded_rectangle([0, 0, pill_w, pill_h], radius=int(pill_h // 2), fill=(accent[0], accent[1], accent[2], 38))
            card.paste(pill_bg, (pill_x, pill_y), pill_bg)
            draw.text((pill_x + int(24 * scale), pill_y + int(8 * scale)), meta["tag"], font=tag_font, fill=accent)

            # Title
            title_y = pill_y + pill_h + int(36 * scale)
            tb = draw.textbbox((0, 0), meta["title"], font=title_font)
            draw.text(((tw - (tb[2] - tb[0])) // 2, title_y), meta["title"], font=title_font, fill=(20, 24, 32))

            # Subtitle
            sub_y = title_y + (tb[3] - tb[1]) + int(24 * scale)
            sb = draw.textbbox((0, 0), meta["subtitle"], font=sub_font)
            draw.text(((tw - (sb[2] - sb[0])) // 2, sub_y), meta["subtitle"], font=sub_font, fill=(90, 98, 115))

            # Screen placement inside device frame
            dev_top = sub_y + (sb[3] - sb[1]) + int(70 * scale)
            margin_x = int(80 * scale)
            frame_w = tw - margin_x * 2
            aspect = im.height / im.width
            frame_h = int(frame_w * aspect)

            # Screen layer
            screen_resized = im.resize((frame_w, frame_h), Image.Resampling.LANCZOS)
            radius = int(50 * scale)

            mask = Image.new("L", (frame_w, frame_h), 0)
            mask_draw = ImageDraw.Draw(mask)
            mask_draw.rounded_rectangle([0, 0, frame_w, frame_h], radius=radius, fill=255)

            # Shadow layer
            shadow = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
            s_draw = ImageDraw.Draw(shadow)
            s_draw.rounded_rectangle([margin_x, dev_top + int(14 * scale), margin_x + frame_w, dev_top + frame_h + int(14 * scale)], radius=radius, fill=(0, 0, 0, 45))
            shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(24 * scale)))
            card.paste(shadow, (0, 0), shadow)

            # Paste screenshot
            card.paste(screen_resized, (margin_x, dev_top), mask)

            # Border
            border_img = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
            b_draw = ImageDraw.Draw(border_img)
            b_draw.rounded_rectangle([0, 0, frame_w, frame_h], radius=radius, outline=(220, 224, 232, 200), width=max(2, int(4 * scale)))
            card.paste(border_img, (margin_x, dev_top), border_img)

            framed_dir = OUTPUT_DIR / f"{size_name}_framed"
            framed_dir.mkdir(parents=True, exist_ok=True)
            framed_out = framed_dir / f"{idx+1:02d}_AppStore_{size_name}.png"
            card.save(framed_out, "PNG")

        print(f"✓ 成功处理截图 {idx+1}: {file_path.name}")

    print("\n所有 App Store 标准尺寸截图处理完成！存放路径:")
    print(f"👉 {OUTPUT_DIR.resolve()}")

if __name__ == "__main__":
    process_screenshots()
