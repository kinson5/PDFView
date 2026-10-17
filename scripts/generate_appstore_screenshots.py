#!/usr/bin/env python3
"""
App Store Screenshot Generator for PDFview
Generates publication-ready App Store promotional screenshots in standard Apple sizes:
- 6.9" Display: 1320 x 2868 (iPhone 16 Pro Max)
- 6.7" Display: 1290 x 2796 (iPhone 15 Pro Max, 14 Pro Max)
- 6.5" Display: 1242 x 2688 (iPhone 11 Pro Max, XS Max)
- 5.5" Display: 1242 x 2208 (iPhone 8 Plus, SE 3)
- 13.0" iPad Pro: 2064 x 2752
"""

import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZES = {
    "iphone_6.9": (1320, 2868),
    "iphone_6.7": (1290, 2796),
    "iphone_6.5": (1242, 2688),
    "iphone_5.5": (1242, 2208),
    "ipad_13.0":  (2064, 2752),
}

SCREENS = [
    {
        "id": "01_smart_reflow",
        "tag": "智能双模式重排",
        "title": "大字畅读 PDF · 重现经典排版",
        "subtitle": "矢量文字横排与高精图形切片，支持本地长图分段重排",
        "gradient": ((245, 247, 252), (230, 236, 248)),
        "accent": (41, 108, 255),
    },
    {
        "id": "02_crop_deskew",
        "tag": "手动切边与方框纠偏",
        "title": "告别倾斜畸变 · 梯形秒变平直",
        "subtitle": "四角自由交互拖拽，透视拉伸纠正拍摄倾斜并切除黑边",
        "gradient": ((248, 245, 255), (236, 230, 252)),
        "accent": (142, 68, 237),
    },
    {
        "id": "03_vertical_ancient",
        "tag": "竖排古籍善本重构",
        "title": "古籍竖排流式化 · 智能逆序重构",
        "subtitle": "专设一键直排复选框，由右至左手势自适应顺滑翻页",
        "gradient": ((255, 248, 242), (250, 235, 222)),
        "accent": (224, 102, 36),
    },
    {
        "id": "04_themes_translate",
        "tag": "护眼纸张与离线翻译",
        "title": "四色温润纸张 · 离线双语对照",
        "subtitle": "羊皮护眼与夜间暗黑主题，集成 Apple 离线多语言翻译",
        "gradient": ((243, 248, 244), (226, 240, 230)),
        "accent": (46, 139, 87),
    },
    {
        "id": "05_icloud_sync",
        "tag": "iCloud 多设备同步",
        "title": "跨设备无缝接力 · 进度实时共享",
        "subtitle": "iPhone、iPad 与 Mac 图书及阅读进度自动双向毫秒级同步",
        "gradient": ((242, 249, 255), (220, 238, 255)),
        "accent": (0, 122, 255),
    },
]

def find_font(size: int, bold: bool = False):
    """Finds an appropriate system font supporting Chinese and Latin typography."""
    if bold:
        candidates = [
            "/System/Library/Fonts/STHeiti Medium.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
        ]
    else:
        candidates = [
            "/System/Library/Fonts/STHeiti Light.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
        ]
    for c in candidates:
        if os.path.exists(c):
            try:
                idx = 1 if (bold and "Hiragino" in c) else 0
                return ImageFont.truetype(c, size, index=idx)
            except Exception:
                pass
    return ImageFont.load_default()

def draw_gradient_background(draw, size, top_color, bottom_color):
    """Draws a vertical linear gradient."""
    width, height = size
    r1, g1, b1 = top_color
    r2, g2, b2 = bottom_color
    for y in range(height):
        factor = y / height
        r = int(r1 + (r2 - r1) * factor)
        g = int(g1 + (g2 - g1) * factor)
        b = int(b1 + (b2 - b1) * factor)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

def draw_appstore_screenshot(screen, width, height, output_path):
    """Renders a single high-resolution App Store promotional screenshot."""
    img = Image.new("RGB", (width, height), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    # 1. Background Gradient
    top_col, bot_col = screen["gradient"]
    draw_gradient_background(draw, (width, height), top_col, bot_col)

    # Scale factors based on 1290 width standard
    scale = width / 1290.0

    # 2. Top Header Elements
    tag_font_size = int(32 * scale)
    title_font_size = int(58 * scale)
    subtitle_font_size = int(34 * scale)

    tag_font = find_font(tag_font_size, bold=True)
    title_font = find_font(title_font_size, bold=True)
    sub_font = find_font(subtitle_font_size, bold=False)

    padding_top = int(140 * scale)

    # Tag pill
    tag_text = screen["tag"]
    tag_bbox = draw.textbbox((0, 0), tag_text, font=tag_font)
    tag_w = tag_bbox[2] - tag_bbox[0]
    tag_h = tag_bbox[3] - tag_bbox[1]

    pill_pad_x = int(24 * scale)
    pill_pad_y = int(10 * scale)
    pill_w = tag_w + pill_pad_x * 2
    pill_h = tag_h + pill_pad_y * 2
    pill_x = (width - pill_w) // 2
    pill_y = padding_top

    # Pill background
    accent_rgb = screen["accent"]
    pill_bg = (accent_rgb[0], accent_rgb[1], accent_rgb[2], 30)
    pill_img = Image.new("RGBA", (pill_w, pill_h), (0, 0, 0, 0))
    pill_draw = ImageDraw.Draw(pill_img)
    pill_draw.rounded_rectangle([0, 0, pill_w, pill_h], radius=int(pill_h // 2), fill=(accent_rgb[0], accent_rgb[1], accent_rgb[2], 38))
    img.paste(pill_img, (pill_x, pill_y), pill_img)

    # Tag text
    draw.text((pill_x + pill_pad_x, pill_y + pill_pad_y - int(2 * scale)), tag_text, font=tag_font, fill=accent_rgb)

    # Title
    title_y = pill_y + pill_h + int(36 * scale)
    title_text = screen["title"]
    title_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    draw.text(((width - title_w) // 2, title_y), title_text, font=title_font, fill=(20, 24, 32))

    # Subtitle
    sub_y = title_y + (title_bbox[3] - title_bbox[1]) + int(24 * scale)
    sub_text = screen["subtitle"]
    sub_bbox = draw.textbbox((0, 0), sub_text, font=sub_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(((width - sub_w) // 2, sub_y), sub_text, font=sub_font, fill=(90, 98, 115))

    # 3. Phone Device Container / Mockup Canvas
    mockup_top = sub_y + (sub_bbox[3] - sub_bbox[1]) + int(70 * scale)
    mockup_margin_x = int(90 * scale)
    mockup_w = width - mockup_margin_x * 2
    mockup_h = height - mockup_top + int(120 * scale)
    mockup_radius = int(54 * scale)

    # Device Outer Frame
    device_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dev_draw = ImageDraw.Draw(device_layer)

    # Device Shadow
    shadow_offset = int(18 * scale)
    dev_draw.rounded_rectangle(
        [mockup_margin_x, mockup_top + shadow_offset, mockup_margin_x + mockup_w, mockup_top + mockup_h + shadow_offset],
        radius=mockup_radius,
        fill=(0, 0, 0, 35)
    )
    device_layer = device_layer.filter(ImageFilter.GaussianBlur(radius=int(22 * scale)))
    img.paste(device_layer, (0, 0), device_layer)

    # Device Body (Pure White phone with border)
    body_img = Image.new("RGBA", (mockup_w, mockup_h), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(body_img)
    b_draw.rounded_rectangle([0, 0, mockup_w, mockup_h], radius=mockup_radius, fill=(255, 255, 255, 255))
    b_draw.rounded_rectangle([0, 0, mockup_w, mockup_h], radius=mockup_radius, outline=(220, 224, 232, 255), width=max(1, int(3 * scale)))

    # Inside Mockup Content (Header + Sample Book / Preview)
    content_pad = int(32 * scale)
    content_w = mockup_w - content_pad * 2

    # App Status Bar & Navigation Bar mockup
    bar_h = int(64 * scale)
    b_draw.rounded_rectangle([content_pad, content_pad, content_pad + content_w, content_pad + bar_h], radius=int(14 * scale), fill=(245, 247, 250, 255))
    
    # Mode switch buttons mockup (原版 | 重排 | OCR)
    mode_w = int(content_w * 0.45)
    b_draw.rounded_rectangle([content_pad + int(10 * scale), content_pad + int(8 * scale), content_pad + int(10 * scale) + mode_w, content_pad + bar_h - int(8 * scale)], radius=int(8 * scale), fill=(230, 234, 242, 255))
    
    # Feature illustration inside phone screen
    illus_y = content_pad + bar_h + int(24 * scale)
    illus_h = mockup_h - illus_y - int(60 * scale)

    # Feature-specific graphics
    draw_screen_graphic(b_draw, screen["id"], content_pad, illus_y, content_w, illus_h, scale, accent_rgb)

    img.paste(body_img, (mockup_margin_x, mockup_top), body_img)

    # Save to disk
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG", quality=95)
    print(f"Generated: {output_path} ({width}x{height})")

def draw_screen_graphic(draw, screen_id, x, y, w, h, scale, accent):
    """Draws specialized visual layout for each of the 5 promotional screens."""
    font_main = find_font(int(26 * scale), bold=True)
    font_sub = find_font(int(20 * scale), bold=False)

    if screen_id == "01_smart_reflow":
        # Multi-column Reflow Comparison
        card_h = int(h * 0.42)
        # Top Card: Graphic Slices
        draw.rounded_rectangle([x, y, x + w, y + card_h], radius=int(16 * scale), fill=(250, 250, 252, 255), outline=(225, 230, 240, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), y + int(20 * scale)), "高清晰图形切片横排 (Graphic Slices)", font=font_main, fill=(30, 36, 50))
        # Simulated lines
        line_y = y + int(64 * scale)
        for i in range(5):
            lw = int(w * (0.85 if i != 4 else 0.55))
            draw.rounded_rectangle([x + int(24 * scale), line_y, x + int(24 * scale) + lw, line_y + int(14 * scale)], radius=int(4 * scale), fill=(180, 190, 205, 200))
            line_y += int(28 * scale)

        # Bottom Card: Vector Text Reflow
        bot_y = y + card_h + int(20 * scale)
        bot_h = int(h * 0.48)
        draw.rounded_rectangle([x, bot_y, x + w, bot_y + bot_h], radius=int(16 * scale), fill=(255, 253, 245, 255), outline=(245, 215, 175, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), bot_y + int(20 * scale)), "无损矢量文字重排 (Vector Text · 50%–300%)", font=font_main, fill=(180, 90, 20))
        line_y = bot_y + int(64 * scale)
        for i in range(6):
            lw = int(w * (0.92 if i != 5 else 0.65))
            draw.rounded_rectangle([x + int(24 * scale), line_y, x + int(24 * scale) + lw, line_y + int(16 * scale)], radius=int(4 * scale), fill=(225, 160, 100, 190))
            line_y += int(32 * scale)

    elif screen_id == "02_crop_deskew":
        # Crop & Deskew Quad Wireframe
        card_h = int(h * 0.88)
        draw.rounded_rectangle([x, y, x + w, y + card_h], radius=int(16 * scale), fill=(247, 244, 254, 255), outline=(220, 205, 245, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), y + int(20 * scale)), "交互式四角与四边纠偏选区", font=font_main, fill=accent)
        # Draw skewed quad in center
        cx = x + w // 2
        cy = y + card_h // 2 + int(10 * scale)
        qw = int(w * 0.36)
        qh = int(card_h * 0.32)
        # Trapezoid coordinates
        p1 = (cx - qw - int(25 * scale), cy - qh + int(15 * scale))
        p2 = (cx + qw + int(35 * scale), cy - qh - int(20 * scale))
        p3 = (cx + qw - int(10 * scale), cy + qh + int(30 * scale))
        p4 = (cx - qw + int(15 * scale), cy + qh - int(10 * scale))
        # Fill polygon
        draw.polygon([p1, p2, p3, p4], fill=(235, 222, 252, 230), outline=accent, width=int(4 * scale))
        # Handles
        for pt in [p1, p2, p3, p4]:
            hr = int(14 * scale)
            draw.ellipse([pt[0] - hr, pt[1] - hr, pt[0] + hr, pt[1] + hr], fill=(255, 255, 255), outline=accent, width=int(4 * scale))

    elif screen_id == "03_vertical_ancient":
        # Vertical Ancient Text Columns
        card_h = int(h * 0.88)
        draw.rounded_rectangle([x, y, x + w, y + card_h], radius=int(16 * scale), fill=(254, 250, 242, 255), outline=(238, 220, 195, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), y + int(20 * scale)), "右起竖排古籍 · 智能逆序流式排版", font=font_main, fill=accent)
        # Vertical text columns
        col_x = x + w - int(60 * scale)
        for col_idx in range(7):
            col_y = y + int(80 * scale)
            for char_idx in range(8):
                draw.rounded_rectangle([col_x - int(18 * scale), col_y, col_x + int(18 * scale), col_y + int(34 * scale)], radius=int(4 * scale), fill=(160, 110, 60, 170))
                col_y += int(46 * scale)
            col_x -= int(58 * scale)

    elif screen_id == "04_themes_translate":
        # 4 Eye-Care Color Themes & Bilingual translation
        card_h = int(h * 0.88)
        draw.rounded_rectangle([x, y, x + w, y + card_h], radius=int(16 * scale), fill=(244, 248, 245, 255), outline=(210, 235, 220, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), y + int(20 * scale)), "护眼纸张色板 · Apple 原生离线双语对照", font=font_main, fill=accent)
        # 4 Circles
        themes = [(255, 255, 255), (247, 240, 222), (228, 243, 230), (45, 47, 52)]
        t_x = x + int(36 * scale)
        t_y = y + int(70 * scale)
        for col in themes:
            cr = int(26 * scale)
            draw.ellipse([t_x, t_y, t_x + cr * 2, t_y + cr * 2], fill=col, outline=(180, 190, 185), width=int(2 * scale))
            t_x += cr * 2 + int(28 * scale)
        # Translation box
        tr_y = t_y + int(80 * scale)
        tr_h = card_h - int(170 * scale)
        draw.rounded_rectangle([x + int(20 * scale), tr_y, x + w - int(20 * scale), tr_y + tr_h], radius=int(12 * scale), fill=(255, 255, 255, 255), outline=(215, 230, 222, 255), width=int(2 * scale))
        draw.text((x + int(36 * scale), tr_y + int(20 * scale)), "【原文】 Artificial Intelligence Reflow Engine", font=font_main, fill=(60, 70, 80))
        draw.text((x + int(36 * scale), tr_y + int(70 * scale)), "【译文】 人工智能排版引擎与自动断行", font=font_main, fill=accent)

    elif screen_id == "05_icloud_sync":
        # Multi-Device iCloud Sync Hub
        card_h = int(h * 0.88)
        draw.rounded_rectangle([x, y, x + w, y + card_h], radius=int(16 * scale), fill=(244, 249, 255, 255), outline=(210, 230, 250, 255), width=int(2 * scale))
        draw.text((x + int(24 * scale), y + int(20 * scale)), "iCloud 云端书库与跨端进度同步", font=font_main, fill=accent)
        # Book list mockup
        list_y = y + int(75 * scale)
        for i, (title, progress) in enumerate([("明代文选刻本.pdf", "第 42 / 120 页 (35%)"), ("Quantum_Mechanics.pdf", "第 18 / 450 页 (4%)"), ("Photo_LongScan.jpg", "第 1 / 1 页 (100%)")]):
            item_h = int(85 * scale)
            draw.rounded_rectangle([x + int(20 * scale), list_y, x + w - int(20 * scale), list_y + item_h], radius=int(10 * scale), fill=(255, 255, 255, 255), outline=(225, 235, 245, 255), width=int(1.5 * scale))
            draw.text((x + int(40 * scale), list_y + int(14 * scale)), title, font=font_main, fill=(35, 45, 60))
            draw.text((x + int(40 * scale), list_y + int(50 * scale)), progress, font=font_sub, fill=accent)
            list_y += item_h + int(18 * scale)

def main():
    output_dir = Path("AppStoreAssets/Screenshots")
    output_dir.mkdir(parents=True, exist_ok=True)

    print("==================================================")
    print("Generating Publication-Ready App Store Screenshots")
    print("==================================================")

    for screen in SCREENS:
        for size_key, (w, h) in SIZES.items():
            fname = f"{screen['id']}_{size_key}_{w}x{h}.png"
            target_path = output_dir / size_key / fname
            draw_appstore_screenshot(screen, w, h, str(target_path))

    print("\n✅ All App Store screenshots generated successfully in:", output_dir.resolve())

if __name__ == "__main__":
    main()
