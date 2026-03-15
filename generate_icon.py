from PIL import Image, ImageDraw, ImageFont
import math
import os

# Create icon with transparent background
size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))  # transparent background
draw = ImageDraw.Draw(img)

# Colors
green = (0, 200, 150, 255)      # #00C896
white = (255, 255, 255, 255)

# Draw green circle background
margin = 80
draw.ellipse([margin, margin, size-margin, size-margin], fill=green)

# Draw letter A
center_x = size // 2
center_y = size // 2

# A shape using polygons
a_width = 320
a_height = 380
a_top = center_y - a_height // 2 - 20
a_bottom = center_y + a_height // 2 - 20

stroke = 70

# Left leg of A
left_leg = [
    (center_x - a_width//2, a_bottom),
    (center_x - a_width//2 + stroke, a_bottom),
    (center_x + stroke//2, a_top),
    (center_x - stroke//2, a_top),
]
draw.polygon(left_leg, fill=white)

# Right leg of A
right_leg = [
    (center_x + a_width//2, a_bottom),
    (center_x + a_width//2 - stroke, a_bottom),
    (center_x + stroke//2, a_top),
    (center_x - stroke//2, a_top),
]
draw.polygon(right_leg, fill=white)

# Crossbar of A
crossbar_y = center_y + 20
crossbar_height = 55
left_x = center_x - a_width//2 + int((crossbar_y - a_bottom) * (center_x - center_x + a_width//2 - stroke) / (a_top - a_bottom)) + stroke - 30
right_x = center_x + a_width//2 - int((crossbar_y - a_bottom) * (center_x - center_x + a_width//2 - stroke) / (a_top - a_bottom)) - stroke + 30

draw.rectangle([left_x, crossbar_y, right_x, crossbar_y + crossbar_height], fill=white)

# Save
output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 
                            'attendance_app', 'assets', 'icon', 'icon.png')
img.save(output_path, 'PNG')
print(f"Icon saved to {output_path}")
print("Now run: dart run flutter_launcher_icons")