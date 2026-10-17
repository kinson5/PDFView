#!/usr/bin/env python3
"""
Generates a modern, high-resolution 1024x1024 App Icon for PDFview
focusing on the core feature: REFLOW (重排).
Visual concept:
- Modern Apple-style rich red gradient background with subtle radial highlight.
- An elegant, pristine white document/canvas in the center.
- Top: signature "PDF" pill badge.
- Left-to-Right dynamic transformation:
  * Left: rigid, dense multi-column fixed text blocks (the original unreadable PDF).
  * Center: fluid curved glowing transition ribbon/arrows representing "Reflow".
  * Right: spacious, crisp, readable, adapted text lines that fit the screen smoothly.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

def create_reflow_icon(output_path="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon_1024_candidate.png"):
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Background Gradient (Rich Vermilion Red to Deep Crimson)
    # Apple style diagonal gradient with subtle radial lighting
    top_color = (245, 56, 56)      # #F53838
    bottom_color = (185, 14, 25)   # #B90E19

    for y in range(size):
        for x in range(size):
            # Diagonal + radial factor
            diag = (x * 0.4 + y * 0.6) / size
            r = int(top_color[0] + (bottom_color[0] - top_color[0]) * diag)
            g = int(top_color[1] + (bottom_color[1] - top_color[1]) * diag)
            b = int(top_color[2] + (bottom_color[2] - top_color[2]) * diag)
            img.putpixel((x, y), (r, g, b, 255))

    # Add soft radial ambient glow near top-left
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_center = (size * 0.3, size * 0.25)
    for radius in range(int(size * 0.7), 0, -4):
        alpha = int(25 * (1.0 - radius / (size * 0.7)))
        glow_draw.ellipse(
            [glow_center[0] - radius, glow_center[1] - radius, glow_center[0] + radius, glow_center[1] + radius],
            fill=(255, 255, 255, alpha)
        )
    img = Image.alpha_composite(img, glow)

    # 2. Central White Document Card (Floating Paper / Mobile Canvas)
    doc_w = int(size * 0.68)   # ~696 pt
    doc_h = int(size * 0.82)   # ~840 pt
    doc_x = (size - doc_w) // 2
    doc_y = (size - doc_h) // 2
    corner_radius = 64

    # Drop Shadow for Document
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_offset_y = 24
    shadow_box = [doc_x, doc_y + shadow_offset_y, doc_x + doc_w, doc_y + doc_h + shadow_offset_y]
    shadow_draw.rounded_rectangle(shadow_box, radius=corner_radius, fill=(50, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(32))
    img = Image.alpha_composite(img, shadow)

    # Document Surface
    doc_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    doc_draw = ImageDraw.Draw(doc_layer)
    doc_box = [doc_x, doc_y, doc_x + doc_w, doc_y + doc_h]
    doc_draw.rounded_rectangle(doc_box, radius=corner_radius, fill=(255, 255, 255, 255))

    # Folded corner at top right (Classic PDF sheet indicator)
    fold_size = 80
    fold_x = doc_x + doc_w - fold_size
    fold_y = doc_y
    # Draw subtle folded corner flap
    doc_draw.polygon(
        [(fold_x, fold_y), (doc_x + doc_w, fold_y + fold_size), (doc_x + doc_w, fold_y)],
        fill=(238, 240, 245, 255)
    )
    doc_draw.polygon(
        [(fold_x, fold_y), (fold_x, fold_y + fold_size), (doc_x + doc_w, fold_y + fold_size)],
        fill=(218, 222, 230, 255)
    )

    # 3. Top Header: Signature Red "PDF" Badge
    badge_w = 260
    badge_h = 76
    badge_x = doc_x + 56
    badge_y = doc_y + 60
    badge_radius = 20
    doc_draw.rounded_rectangle(
        [badge_x, badge_y, badge_x + badge_w, badge_y + badge_h],
        radius=badge_radius,
        fill=(220, 28, 38, 255)
    )

    # "PDF" text inside badge (Bold, centered)
    try:
        font_pdf = ImageFont.truetype("/System/Library/Fonts/SFProRounded.ttf", 46)
    except:
        try:
            font_pdf = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 46)
        except:
            font_pdf = ImageFont.load_default()

    bbox = doc_draw.textbbox((0, 0), "PDF", font=font_pdf)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    text_x = badge_x + (badge_w - text_w) // 2
    text_y = badge_y + (badge_h - text_h) // 2 - 4
    doc_draw.text((text_x, text_y), "PDF", fill=(255, 255, 255, 255), font=font_pdf)

    # Sub-badge "REFLOW / 智能重排" tag in vibrant blue
    tag_w = 140
    tag_h = 36
    tag_x = badge_x + badge_w + 20
    tag_y = badge_y + (badge_h - tag_h) // 2
    doc_draw.rounded_rectangle(
        [tag_x, tag_y, tag_x + tag_w, tag_y + tag_h],
        radius=12,
        fill=(0, 113, 227, 24)
    )
    doc_draw.rounded_rectangle(
        [tag_x, tag_y, tag_x + tag_w, tag_y + tag_h],
        radius=12,
        outline=(0, 113, 227, 180),
        width=2
    )
    try:
        font_tag = ImageFont.truetype("/System/Library/Fonts/SFProRounded.ttf", 20)
    except:
        font_tag = ImageFont.load_default()
    tag_bbox = doc_draw.textbbox((0, 0), "REFLOW", font=font_tag)
    tag_text_w = tag_bbox[2] - tag_bbox[0]
    doc_draw.text((tag_x + (tag_w - tag_text_w) // 2, tag_y + 8), "REFLOW", fill=(0, 113, 227, 255), font=font_tag)

    # 4. Reflow Transformation Graphic (The Heart of the Icon!)
    # Section A: Original Rigid Multi-Column Miniature Box (Before Reflow)
    # Positioned on the left side
    col_box_x = doc_x + 56
    col_box_y = doc_y + 176
    col_box_w = 210
    col_box_h = 240
    col_corner = 16

    # Soft gray container for the original page
    doc_draw.rounded_rectangle(
        [col_box_x, col_box_y, col_box_x + col_box_w, col_box_y + col_box_h],
        radius=col_corner,
        fill=(245, 247, 250, 255),
        outline=(220, 224, 232, 255),
        width=2
    )

    # Dense, tight, 2-column miniature text lines in the container
    col1_x = col_box_x + 18
    col2_x = col_box_x + 112
    col_line_w = 80
    dense_color = (165, 175, 190, 255)
    header_color = (120, 132, 150, 255)

    # Column 1 lines
    doc_draw.rounded_rectangle([col1_x, col_box_y + 20, col1_x + 50, col_box_y + 28], radius=4, fill=header_color)
    for i in range(8):
        ly = col_box_y + 40 + i * 18
        lw = col_line_w if i % 4 != 3 else 55
        doc_draw.rounded_rectangle([col1_x, ly, col1_x + lw, ly + 8], radius=4, fill=dense_color)

    # Column 2 lines
    doc_draw.rounded_rectangle([col2_x, col_box_y + 20, col2_x + 65, col2_x + 28], radius=4, fill=header_color)
    for i in range(8):
        ly = col_box_y + 40 + i * 18
        lw = col_line_w if i % 3 != 2 else 60
        doc_draw.rounded_rectangle([col2_x, ly, col2_x + lw, ly + 8], radius=4, fill=dense_color)

    # Tiny badge on original: "密集原版" label dot
    doc_draw.rounded_rectangle([col_box_x + 18, col_box_y + col_box_h - 26, col_box_x + 60, col_box_y + col_box_h - 14], radius=6, fill=(200, 208, 220, 255))

    # Section B: Dynamic Reflow Flow Ribbon / Arrows
    # Vibrant gradient flowing from the rigid columns into the reflowed text
    flow_start_x = col_box_x + col_box_w + 12
    flow_start_y = col_box_y + 120
    flow_end_x = doc_x + doc_w - 56
    flow_end_y = doc_y + 220

    # Draw dynamic transformation wave & arrows
    # A glowing gradient curved path / flow ribbon
    flow_ribbon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    flow_draw = ImageDraw.Draw(flow_ribbon)

    # Reflow flow arrow / dynamic wave
    arrow_pts = [
        (flow_start_x + 10, col_box_y + 70),
        (flow_start_x + 46, col_box_y + 60),
        (flow_start_x + 46, col_box_y + 50),
        (flow_start_x + 82, col_box_y + 75),
        (flow_start_x + 46, col_box_y + 100),
        (flow_start_x + 46, col_box_y + 90),
        (flow_start_x + 10, col_box_y + 80)
    ]
    flow_draw.polygon(arrow_pts, fill=(0, 122, 255, 230))

    # Upper reflow text row (adapted headline)
    headline_x = flow_start_x + 100
    headline_y = col_box_y + 54
    headline_w = doc_x + doc_w - headline_x - 56
    doc_draw.rounded_rectangle([headline_x, headline_y, headline_x + headline_w, headline_y + 20], radius=8, fill=(0, 113, 227, 255))

    # Sub-headline
    sub_y = headline_y + 36
    doc_draw.rounded_rectangle([headline_x, sub_y, headline_x + int(headline_w * 0.72), sub_y + 16], radius=6, fill=(100, 150, 220, 220))

    # Section C: Main Reflow Flowing Paragraphs (The Beautiful Adapted Result!)
    # Broad, spacious, perfectly proportioned lines running across the bottom
    main_reflow_y = col_box_y + col_box_h + 36
    main_reflow_x = doc_x + 56
    main_reflow_w = doc_w - 112

    # A subtle visual separator with a Reflow symbol (staggered bars / text.alignleft emblem)
    flow_icon_x = main_reflow_x
    flow_icon_y = main_reflow_y
    flow_icon_size = 32

    # Section divider label: "动态流式重排"
    divider_y = main_reflow_y - 12
    doc_draw.line([(main_reflow_x, divider_y), (main_reflow_x + main_reflow_w, divider_y)], fill=(235, 238, 245, 255), width=2)

    # Spacious Reflow Lines with realistic paragraph cadence & vibrant accent
    # Line 1 (Full width, crisp primary dark slate)
    line_h = 24
    line_gap = 18
    text_primary = (30, 41, 59, 255)      # Slate 800
    text_secondary = (71, 85, 105, 255)   # Slate 600
    text_tertiary = (148, 163, 184, 255)  # Slate 400
    accent_blue = (0, 122, 255, 255)      # iOS System Blue

    reflow_lines = [
        (1.0, text_primary, True),       # Line 1: Full width, with accent start
        (0.92, text_primary, False),     # Line 2
        (0.96, text_secondary, False),   # Line 3
        (0.68, text_secondary, False),   # Line 4 (End of para 1)
        (0.94, text_primary, True),      # Line 5: Para 2 start
        (0.85, text_secondary, False),   # Line 6
        (0.50, text_tertiary, False)     # Line 7 (End of para 2)
    ]

    curr_y = main_reflow_y + 14
    for idx, (width_ratio, color, is_para_start) in enumerate(reflow_lines):
        w = int(main_reflow_w * width_ratio)
        lx = main_reflow_x
        
        # Paragraph indent for paragraph start
        if is_para_start:
            indent = 38
            lx += indent
            w -= indent
            # Add an elegant blue bullet or initial marker for visual interest
            doc_draw.ellipse([main_reflow_x + 4, curr_y + 4, main_reflow_x + 20, curr_y + 20], fill=accent_blue)

        doc_draw.rounded_rectangle(
            [lx, curr_y, lx + w, curr_y + line_h],
            radius=10,
            fill=color
        )
        curr_y += line_h + line_gap

    # Merge layers
    img = Image.alpha_composite(img, doc_layer)
    img = Image.alpha_composite(img, flow_ribbon)

    # 5. Clean squircle mask border highlight
    border_highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(border_highlight)
    # Subtle inner border to give crisp definition on all backgrounds
    b_draw.rectangle([0, 0, size, size], outline=(255, 255, 255, 28), width=3)
    img = Image.alpha_composite(img, border_highlight)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Generated reflow icon at: {output_path}")

if __name__ == "__main__":
    create_reflow_icon()
