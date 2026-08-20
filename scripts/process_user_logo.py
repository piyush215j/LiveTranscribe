#!/usr/bin/env python3
"""
process_user_logo.py — LiveTranscribe
Tightly crops the user logo artwork, centers it on a 1500x1500 pure white canvas,
applies macOS squircle rounding, and generates all AppIcon PNG sizes.

v3: Uses colorsys HSV saturation to reliably isolate colored/dark logo pixels
    from white/near-white and grey backgrounds, regardless of alpha channel state.
"""

import os
import colorsys
from PIL import Image, ImageDraw


def find_artwork_bbox(img: Image.Image) -> tuple:
    """
    Scans every pixel to find the tightest box around colored or dark artwork.
    Ignores white, near-white, and grey (low-saturation, high-luminance) pixels.
    Returns (x1, y1, x2, y2) or None.
    """
    rgb = img.convert("RGB")
    w, h = rgb.size

    min_x, min_y = w, h
    max_x, max_y = 0, 0
    found = False

    for y in range(h):
        for x in range(w):
            r, g, b = rgb.getpixel((x, y))
            r_n, g_n, b_n = r / 255.0, g / 255.0, b / 255.0
            _, sat, _ = colorsys.rgb_to_hsv(r_n, g_n, b_n)
            luminance = 0.299 * r + 0.587 * g + 0.114 * b

            # A "logo pixel" is: meaningfully colorful (sat > 12%) OR truly dark
            if sat > 0.12 or luminance < 80:
                if x < min_x: min_x = x
                if y < min_y: min_y = y
                if x > max_x: max_x = x
                if y > max_y: max_y = y
                found = True

    return (min_x, min_y, max_x + 1, max_y + 1) if found else None


def process_logo():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_path = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "logo_source.png")
    assets_dir = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "Assets.xcassets", "AppIcon.appiconset")

    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found.")
        return

    print(f"✓ Loading source: {source_path}")
    orig = Image.open(source_path).convert("RGBA")
    orig_w, orig_h = orig.size
    print(f"  Source dimensions: {orig_w}x{orig_h}")

    # 1. Find the true artwork bounding box using saturation/luminance detection
    print("  Detecting logo artwork pixels...")
    bbox = find_artwork_bbox(orig)

    if not bbox:
        print("Error: Could not detect any logo artwork pixels.")
        return

    bx1, by1, bx2, by2 = bbox
    aw = bx2 - bx1
    ah = by2 - by1
    print(f"✓ Logo detected at: ({bx1},{by1}) → ({bx2},{by2}), size: {aw}x{ah}")

    # Add 5% padding buffer around the detected logo so edges aren't clipped
    pad = int(max(aw, ah) * 0.05)
    bx1 = max(0, bx1 - pad)
    by1 = max(0, by1 - pad)
    bx2 = min(orig_w, bx2 + pad)
    by2 = min(orig_h, by2 + pad)

    # Crop to artwork only
    artwork = orig.crop((bx1, by1, bx2, by2))
    aw, ah = artwork.size
    print(f"✓ Cropped size (with {pad}px padding): {aw}x{ah}")

    # 2. Create 1500x1500 pure white canvas
    canvas_size = 1500
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 255))

    # Fit the logo within 78% of the canvas (industry standard safe zone for macOS icons)
    safe_zone = int(canvas_size * 0.78)
    aspect = float(aw) / float(ah)

    if aspect >= 1.0:
        target_w = safe_zone
        target_h = int(safe_zone / aspect)
    else:
        target_h = safe_zone
        target_w = int(safe_zone * aspect)

    print(f"  Rendering at: {target_w}x{target_h} (inside {canvas_size}x{canvas_size} canvas)")
    artwork_resized = artwork.resize((target_w, target_h), Image.Resampling.LANCZOS)

    # 3. Paste at EXACT geometric center
    paste_x = (canvas_size - target_w) // 2
    paste_y = (canvas_size - target_h) // 2
    print(f"✓ Centered at: X={paste_x}, Y={paste_y}")

    # Composite with white background for any semi-transparent edges
    canvas.paste(artwork_resized, (paste_x, paste_y), artwork_resized)

    # 4. Apply macOS squircle mask
    icon_master = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    margin = int(canvas_size * 0.02)
    corner_radius = int(canvas_size * 0.22)
    box = [margin, margin, canvas_size - margin, canvas_size - margin]

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box, radius=corner_radius, fill=255)

    # Subtle light border around the squircle
    border_draw = ImageDraw.Draw(canvas)
    border_draw.rounded_rectangle(
        box, radius=corner_radius,
        outline=(200, 205, 210, 200),
        width=max(2, int(canvas_size * 0.007))
    )

    icon_master.paste(canvas, (0, 0), mask)

    # 5. Save all macOS AppIcon sizes
    os.makedirs(assets_dir, exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512, 1024]

    for sz in sizes:
        resized = icon_master.resize((sz, sz), Image.Resampling.LANCZOS)
        filename = f"icon_{sz}x{sz}.png"
        filepath = os.path.join(assets_dir, filename)
        resized.save(filepath, "PNG")
        print(f"✓ Generated {filename}")

    # Save a 1024 preview for quick visual inspection
    preview_path = os.path.join(script_dir, "..", "LiveTranscribe", "Resources", "icon_preview_1024.png")
    icon_master.resize((1024, 1024), Image.Resampling.LANCZOS).save(preview_path, "PNG")
    print(f"✓ Saved preview → {os.path.abspath(preview_path)}")

    # 6. Write Xcode Contents.json
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

    # 7. Generate native macOS AppIcon.icns using iconutil
    import shutil
    iconset_temp = os.path.join(script_dir, "..", "build", "AppIcon.iconset")
    os.makedirs(iconset_temp, exist_ok=True)
    icns_map = {
        16: ["icon_16x16.png"],
        32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"],
        128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"],
        1024: ["icon_512x512@2x.png"]
    }
    for sz, names in icns_map.items():
        resized = icon_master.resize((sz, sz), Image.Resampling.LANCZOS)
        for name in names:
            resized.save(os.path.join(iconset_temp, name), "PNG")

    resources_dir = os.path.join(script_dir, "..", "LiveTranscribe", "Resources")
    icns_path = os.path.join(resources_dir, "AppIcon.icns")
    os.system(f"iconutil -c icns '{iconset_temp}' -o '{icns_path}'")
    shutil.rmtree(iconset_temp, ignore_errors=True)
    print(f"✓ Generated AppIcon.icns → {icns_path}")

    print("\n✅ Done — logo is big, perfectly centered, and all icon sizes and AppIcon.icns regenerated.")


if __name__ == "__main__":
    process_logo()
