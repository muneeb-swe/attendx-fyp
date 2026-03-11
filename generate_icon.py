from PIL import Image, ImageDraw, ImageFont
import os

# Create 1024x1024 icon
size = 1024
img = Image.new('RGB', (size, size), color='#0A0A0F')
draw = ImageDraw.Draw(img)

# Draw circle background
margin = 80
draw.ellipse(
    [margin, margin, size-margin, size-margin],
    fill='#141420'
)

# Draw "A" letter
cx, cy = size // 2, size // 2

# Draw big A shape manually
# Triangle/A shape in green
points_A = [
    (cx, cy - 280),           # top
    (cx - 220, cy + 200),     # bottom left
    (cx - 120, cy + 200),     # bottom left inner
    (cx, cy - 80),            # inner top
    (cx + 120, cy + 200),     # bottom right inner
    (cx + 220, cy + 200),     # bottom right
]
draw.polygon(points_A, fill='#00C896')

# Crossbar of A
draw.rectangle(
    [cx - 150, cy + 20, cx + 150, cy + 100],
    fill='#0A0A0F'
)

# Draw X in white (small, bottom right)
x_cx, x_cy = cx + 160, cy + 220
x_size = 80
x_thick = 18
# X shape
draw.line(
    [x_cx - x_size//2, x_cy - x_size//2,
     x_cx + x_size//2, x_cy + x_size//2],
    fill='white', width=x_thick
)
draw.line(
    [x_cx + x_size//2, x_cy - x_size//2,
     x_cx - x_size//2, x_cy + x_size//2],
    fill='white', width=x_thick
)

# Save
os.makedirs('attendance_app/assets/icon', exist_ok=True)
img.save('attendance_app/assets/icon/icon.png')
print("Icon generated successfully!")