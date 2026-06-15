#!/usr/bin/env python3
"""Generate app icon for Watermark Camera"""

from PIL import Image, ImageDraw, ImageFont
import math

# Create 1024x1024 icon
size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Background gradient (deep blue to cyan)
for y in range(size):
    ratio = y / size
    r = int(20 + (40 - 20) * ratio)
    g = int(60 + (130 - 60) * ratio)
    b = int(120 + (180 - 120) * ratio)
    draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

# Draw camera body (rounded rectangle)
camera_color = (255, 255, 255, 240)
camera_x, camera_y = 200, 300
camera_w, camera_h = 624, 424
camera_r = 60
draw.rounded_rectangle([camera_x, camera_y, camera_x + camera_w, camera_y + camera_h], radius=camera_r, fill=camera_color)

# Camera top flash
flash_x, flash_y = 280, 240
flash_w, flash_h = 120, 80
draw.rounded_rectangle([flash_x, flash_y, flash_x + flash_w, flash_y + flash_h], radius=20, fill=camera_color)

# Camera lens (circle)
lens_cx, lens_cy = 512, 512
lens_r = 140
# Outer ring
draw.ellipse([lens_cx - lens_r - 20, lens_cy - lens_r - 20, lens_cx + lens_r + 20, lens_cy + lens_r + 20], fill=(60, 80, 100, 255))
# Inner ring
draw.ellipse([lens_cx - lens_r, lens_cy - lens_r, lens_cx + lens_r, lens_cy + lens_r], fill=(30, 50, 70, 255))
# Lens center
inner_r = 90
draw.ellipse([lens_cx - inner_r, lens_cy - inner_r, lens_cx + inner_r, lens_cy + inner_r], fill=(80, 120, 160, 255))
# Highlight
hl_r = 40
draw.ellipse([lens_cx - hl_r - 30, lens_cy - hl_r - 30, lens_cx + hl_r - 30, lens_cy + hl_r - 30], fill=(150, 200, 255, 200))

# Location pin (bottom right)
pin_cx, pin_cy = 750, 700
pin_r = 60
# Pin body (circle + triangle)
draw.ellipse([pin_cx - pin_r, pin_cy - pin_r, pin_cx + pin_r, pin_cy + pin_r], fill=(255, 80, 80, 255))
# Pin point
draw.polygon([(pin_cx - 30, pin_cy + 40), (pin_cx + 30, pin_cy + 40), (pin_cx, pin_cy + 100)], fill=(255, 80, 80, 255))
# Pin center
draw.ellipse([pin_cx - 25, pin_cy - 25, pin_cx + 25, pin_cy + 25], fill=(255, 255, 255, 255))

# Save icon
output_dir = r'd:\Personal\p\CameraApp\CameraApp\Assets.xcassets\AppIcon.appiconset'
import os
os.makedirs(output_dir, exist_ok=True)

# Save 1024x1024
img.save(os.path.join(output_dir, 'icon-1024.png'))

# Generate other sizes
sizes = [40, 58, 60, 80, 87, 120, 180]
for s in sizes:
    resized = img.resize((s, s), Image.LANCZOS)
    resized.save(os.path.join(output_dir, f'icon-{s}.png'))

# Create Contents.json
contents = {
    "images": [
        {"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-1024.png"},
    ],
    "info": {
        "version": 1,
        "author": "xcode"
    }
}

import json
with open(os.path.join(output_dir, 'Contents.json'), 'w') as f:
    json.dump(contents, f, indent=2)

print("Icon generated successfully!")
print(f"Output: {output_dir}")
