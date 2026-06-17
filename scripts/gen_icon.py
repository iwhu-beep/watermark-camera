#!/usr/bin/env python3
"""Generate iOS app icon for CameraApp."""

from PIL import Image, ImageDraw, ImageFont
import os
import math

SIZE = 1024
img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Rounded rectangle background with gradient
def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

# Create gradient background (deep blue to teal)
for y in range(SIZE):
    t = y / SIZE
    # Gradient: top=#1a73e8 (blue) -> bottom=#0d47a1 (dark blue)
    r = int(26 + (13 - 26) * t)
    g = int(115 + (71 - 115) * t)
    b = int(232 + (161 - 232) * t)
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

# Apply rounded corners mask
mask = Image.new('L', (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
corner_r = int(SIZE * 0.2237)  # iOS standard corner radius ratio
mask_draw.rounded_rectangle([0, 0, SIZE-1, SIZE-1], radius=corner_r, fill=255)
img.putalpha(mask)

draw = ImageDraw.Draw(img)

# Draw camera lens (outer ring)
cx, cy = SIZE // 2, SIZE // 2 - 20
outer_r = 260
for r_offset in range(30):
    r = outer_r - r_offset
    alpha = 255 - int(r_offset * 4)
    color = (255, 255, 255, max(alpha, 80))
    draw.ellipse([cx-r, cy-r, cx+r, cy+r], outline=color, width=2)

# Inner dark circle
inner_r = 200
draw.ellipse([cx-inner_r, cy-inner_r, cx+inner_r, cy+inner_r], fill=(20, 30, 60))

# Lens reflection gradient
for r_offset in range(inner_r):
    t = r_offset / inner_r
    alpha = int(120 * (1 - t))
    color = (100, 180, 255, alpha)
    r = inner_r - r_offset
    x0, y0 = cx - r + 30, cy - r - 20
    x1, y1 = cx + r - 30, cy + r - 20
    if x1 > x0 and y1 > y0:
        draw.ellipse([x0, y0, x1, y1], fill=color)

# Center dot (aperture)
dot_r = 60
draw.ellipse([cx-dot_r, cy-dot_r, cx+dot_r, cy+dot_r], fill=(10, 20, 50))

# Small highlight
hl_r = 25
hl_x, hl_y = cx - 80, cy - 80
draw.ellipse([hl_x-hl_r, hl_y-hl_r, hl_x+hl_r, hl_y+hl_r], fill=(255, 255, 255, 180))

# Draw "W" watermark badge in bottom-right
badge_cx, badge_cy = SIZE - 220, SIZE - 200
badge_r = 100
# Badge circle
draw.ellipse([badge_cx-badge_r, badge_cy-badge_r, badge_cx+badge_r, badge_cy+badge_r], 
             fill=(255, 152, 0))  # Orange badge
# Badge border
for i in range(4):
    draw.ellipse([badge_cx-badge_r-i, badge_cy-badge_r-i, badge_cx+badge_r+i, badge_cy+badge_r+i], 
                 outline=(255, 255, 255, 200), width=1)

# "W" letter
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 120)
except:
    font = ImageFont.load_default()

text = "W"
bbox = draw.textbbox((0, 0), text, font=font)
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]
tx = badge_cx - tw // 2
ty = badge_cy - th // 2 - bbox[1]
draw.text((tx, ty), text, fill=(255, 255, 255), font=font)

# Save master icon
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, 'CameraApp', 'Assets.xcassets', 'AppIcon.appiconset')
os.makedirs(output_dir, exist_ok=True)

# Save 1024x1024 master
img.save(os.path.join(output_dir, 'icon-1024.png'))

# Generate all required sizes for iOS
sizes = {
    'icon-1024.png': 1024,
    'icon-180.png': 180,   # 60pt @3x
    'icon-120.png': 120,   # 60pt @2x
    'icon-87.png': 87,     # 29pt @3x
    'icon-80.png': 80,     # 40pt @2x
    'icon-60.png': 60,     # 20pt @3x
    'icon-58.png': 58,     # 29pt @2x
    'icon-40.png': 40,     # 20pt @2x
}

for name, size in sizes.items():
    if name == 'icon-1024.png':
        continue  # Already saved
    resized = img.resize((size, size), Image.LANCZOS)
    resized.save(os.path.join(output_dir, name))

# Create Contents.json
contents = {
    "images": [
        {"idiom": "iphone", "scale": "2x", "size": "20x20", "filename": "icon-40.png"},
        {"idiom": "iphone", "scale": "3x", "size": "20x20", "filename": "icon-60.png"},
        {"idiom": "iphone", "scale": "2x", "size": "29x29", "filename": "icon-58.png"},
        {"idiom": "iphone", "scale": "3x", "size": "29x29", "filename": "icon-87.png"},
        {"idiom": "iphone", "scale": "2x", "size": "40x40", "filename": "icon-80.png"},
        {"idiom": "iphone", "scale": "3x", "size": "40x40", "filename": "icon-120.png"},
        {"idiom": "iphone", "scale": "2x", "size": "60x60", "filename": "icon-120.png"},
        {"idiom": "iphone", "scale": "3x", "size": "60x60", "filename": "icon-180.png"},
        {"idiom": "ios-marketing", "scale": "1x", "size": "1024x1024", "filename": "icon-1024.png"}
    ],
    "info": {
        "version": 1,
        "author": "xcode"
    }
}

import json
with open(os.path.join(output_dir, 'Contents.json'), 'w') as f:
    json.dump(contents, f, indent=2)

# Also create parent Contents.json
parent_dir = os.path.join(base_dir, 'CameraApp', 'Assets.xcassets')
with open(os.path.join(parent_dir, 'Contents.json'), 'w') as f:
    json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)

print(f"Icon generated at: {output_dir}")
print(f"Files: {os.listdir(output_dir)}")
