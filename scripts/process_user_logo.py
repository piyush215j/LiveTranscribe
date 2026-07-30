#!/usr/bin/env python3
"""
process_user_logo.py — LiveTranscribe
Tightly crops the user logo artwork, centers it on a 1500x1500 pure white canvas,
applies macOS squircle rounding, and generates all AppIcon PNG sizes.
"""

import os
from PIL import Image, ImageDraw

def process_logo():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_path = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "logo_source.png")
    assets_dir = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "Assets.xcassets", "AppIcon.appiconset")

    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found.")
        return

    # Open image
    orig = Image.open(source_path).convert("RGBA")

    # 1. Tightly find bounding box of non-white artwork pixels
    gray = orig.convert("L")
    bw = gray.point(lambda p: 255 if p < 240 else 0)
    bbox = bw.getbbox()

    if not bbox:
        print("Error: Could not find artwork bounding box.")
        return

    # Tightly crop the microphone artwork
    artwork = orig.crop(bbox)
    aw, ah = artwork.size
    print(f"✓ Cropped artwork size: {aw}x{ah}")

    # 2. Create 1500x1500 pure white canvas
    canvas_size = 1500
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 255))

    # Target artwork size inside 1500x1500 canvas (fit within ~1050x1050 area)
    max_target = 1050
    aspect = float(aw) / float(ah)

    if aw > ah:
        target_w = max_target
        target_h = int(max_target / aspect)
    else:
        target_h = max_target
        target_w = int(max_target * aspect)

    artwork_resized = artwork.resize((target_w, target_h), Image.Resampling.LANCZOS)

    # 3. Paste artwork at EXACT center of 1500x1500 canvas
    center_x = int((canvas_size - target_w) / 2)
    center_y = int((canvas_size - target_h) / 2)

    # Convert any white background in artwork_resized to match solid white
    canvas.paste(artwork_resized, (center_x, center_y), artwork_resized)
    print(f"✓ Centered artwork at X:{center_x}, Y:{center_y}")

    # 4. Apply macOS squircle mask to 1500x1500 canvas
    icon_1500 = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    margin = int(canvas_size * 0.05)
    corner_radius = int(canvas_size * 0.22)
    box = [margin, margin, canvas_size - margin, canvas_size - margin]

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box, radius=corner_radius, fill=255)

    # Soft subtle border around white squircle card
    border_draw = ImageDraw.Draw(canvas)
    border_draw.rounded_rectangle(box, radius=corner_radius, outline=(210, 215, 220, 255), width=int(canvas_size * 0.01))

    icon_1500.paste(canvas, (0, 0), mask)

    # 5. Save all macOS AppIcon resolutions from 1500x1500 master
    os.makedirs(assets_dir, exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for sz in sizes:
        resized = icon_1500.resize((sz, sz), Image.Resampling.LANCZOS)
        filename = f"icon_{sz}x{sz}.png"
        filepath = os.path.join(assets_dir, filename)
        resized.save(filepath, "PNG")
        print(f"✓ Generated {filename}")

    # Generate Xcode Contents.json
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

    print("✓ AppIcon.appiconset successfully updated with centered 1500x1500 white logo!")

if __name__ == "__main__":
    process_logo()
