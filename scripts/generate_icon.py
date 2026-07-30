#!/usr/bin/env python3
"""
generate_icon.py — LiveTranscribe
Generates native macOS app icon set (1024x1024 down to 16x16)
with a sleek dark squircle and glowing violet/cyan audio waveform.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter

def create_app_icon(size=1024):
    # Canvas
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Margin & Radius for macOS squircle
    margin = int(size * 0.08)
    corner_radius = int(size * 0.22)
    box = [margin, margin, size - margin, size - margin]

    # Draw rounded rectangle background (dark navy blue / violet gradient)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    bg_draw.rounded_rectangle(box, radius=corner_radius, fill=(18, 14, 32, 255))

    # Inner subtle glow border
    bg_draw.rounded_rectangle(box, radius=corner_radius, outline=(140, 80, 255, 180), width=int(size * 0.015))
    img = Image.alpha_composite(img, bg)

    # Draw Audio Waveform Bars (glowing cyan / purple gradient)
    waveform_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wave_draw = ImageDraw.Draw(waveform_layer)

    center_x = size / 2
    center_y = size / 2
    num_bars = 7
    bar_width = int(size * 0.05)
    gap = int(size * 0.04)

    # Heights for symmetrical waveform
    bar_height_factors = [0.3, 0.5, 0.75, 0.9, 0.75, 0.5, 0.3]
    total_width = num_bars * bar_width + (num_bars - 1) * gap
    start_x = center_x - (total_width / 2)

    for i in range(num_bars):
        bx = start_x + i * (bar_width + gap)
        bh = (size * 0.5) * bar_height_factors[i]
        top_y = center_y - (bh / 2)
        bot_y = center_y + (bh / 2)
        bar_box = [int(bx), int(top_y), int(bx + bar_width), int(bot_y)]

        # Gradient color interpolation (cyan -> violet)
        ratio = i / float(num_bars - 1)
        r = int(50 + ratio * 150)
        g = int(220 - ratio * 100)
        b = int(255)
        color = (r, g, b, 240)

        wave_draw.rounded_rectangle(bar_box, radius=bar_width // 2, fill=color)

    # Add a soft glow behind the waveform
    glow_layer = waveform_layer.filter(ImageFilter.GaussianBlur(radius=int(size * 0.04)))
    img = Image.alpha_composite(img, glow_layer)
    img = Image.alpha_composite(img, waveform_layer)

    return img

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(assets_dir, exist_ok=True)

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    base_img = create_app_icon(1024)

    images_json = []

    for sz in sizes:
        resized = base_img.resize((sz, sz), Image.Resampling.LANCZOS)
        filename = f"icon_{sz}x{sz}.png"
        filepath = os.path.join(assets_dir, filename)
        resized.save(filepath, "PNG")
        print(f"✓ Generated {filename}")

    # Generate complete Contents.json for Xcode
    contents_json = """{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64x64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024x1024.png" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}"""

    with open(os.path.join(assets_dir, "Contents.json"), "w") as f:
        f.write(contents_json)

    print("✓ Updated AppIcon.appiconset Contents.json")

if __name__ == "__main__":
    main()
