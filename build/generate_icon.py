#!/usr/bin/env python3
"""Generate MarkView app icon as PNG files for iconutil."""
import struct
import zlib
import os

def create_png(width, height, pixels):
    """Create a PNG file from RGBA pixel data."""
    def chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack('>I', len(data)) + c + crc

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter: none
        for x in range(width):
            idx = (y * width + x) * 4
            raw += bytes(pixels[idx:idx+4])

    idat = chunk(b'IDAT', zlib.compress(raw, 9))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend


def draw_icon(size):
    """Draw MarkView icon at given size."""
    pixels = [0] * (size * size * 4)

    def set_pixel(x, y, r, g, b, a=255):
        if 0 <= x < size and 0 <= y < size:
            idx = (y * size + x) * 4
            # Alpha blend
            if pixels[idx + 3] > 0 and a < 255:
                old_a = pixels[idx + 3] / 255
                new_a = a / 255
                out_a = new_a + old_a * (1 - new_a)
                if out_a > 0:
                    pixels[idx] = int((r * new_a + pixels[idx] * old_a * (1 - new_a)) / out_a)
                    pixels[idx+1] = int((g * new_a + pixels[idx+1] * old_a * (1 - new_a)) / out_a)
                    pixels[idx+2] = int((b * new_a + pixels[idx+2] * old_a * (1 - new_a)) / out_a)
                    pixels[idx+3] = int(out_a * 255)
            else:
                pixels[idx] = r
                pixels[idx+1] = g
                pixels[idx+2] = b
                pixels[idx+3] = a

    def fill_rect(x1, y1, x2, y2, r, g, b, a=255):
        for y in range(max(0, y1), min(size, y2)):
            for x in range(max(0, x1), min(size, x2)):
                set_pixel(x, y, r, g, b, a)

    def fill_rounded_rect(x1, y1, x2, y2, radius, r, g, b, a=255):
        for y in range(max(0, y1), min(size, y2)):
            for x in range(max(0, x1), min(size, x2)):
                # Check corners
                in_rect = True
                # Top-left
                if x < x1 + radius and y < y1 + radius:
                    dx = x - (x1 + radius)
                    dy = y - (y1 + radius)
                    if dx*dx + dy*dy > radius*radius:
                        in_rect = False
                # Top-right
                if x >= x2 - radius and y < y1 + radius:
                    dx = x - (x2 - radius - 1)
                    dy = y - (y1 + radius)
                    if dx*dx + dy*dy > radius*radius:
                        in_rect = False
                # Bottom-left
                if x < x1 + radius and y >= y2 - radius:
                    dx = x - (x1 + radius)
                    dy = y - (y2 - radius - 1)
                    if dx*dx + dy*dy > radius*radius:
                        in_rect = False
                # Bottom-right
                if x >= x2 - radius and y >= y2 - radius:
                    dx = x - (x2 - radius - 1)
                    dy = y - (y2 - radius - 1)
                    if dx*dx + dy*dy > radius*radius:
                        in_rect = False
                if in_rect:
                    set_pixel(x, y, r, g, b, a)

    def fill_circle(cx, cy, radius, r, g, b, a=255):
        for y in range(max(0, int(cy - radius - 1)), min(size, int(cy + radius + 2))):
            for x in range(max(0, int(cx - radius - 1)), min(size, int(cx + radius + 2))):
                dx = x - cx
                dy = y - cy
                dist = (dx*dx + dy*dy) ** 0.5
                if dist <= radius:
                    set_pixel(x, y, r, g, b, a)
                elif dist <= radius + 1:
                    edge_a = int(a * (1 - (dist - radius)))
                    if edge_a > 0:
                        set_pixel(x, y, r, g, b, edge_a)

    s = size  # shorthand
    pad = s // 8
    corner = s // 5

    # Background: rounded rectangle with gradient blue
    fill_rounded_rect(0, 0, s, s, corner, 30, 100, 220)

    # Slight gradient effect - lighter at top
    for y in range(s // 3):
        alpha = int(40 * (1 - y / (s // 3)))
        for x in range(s):
            # Check if inside the rounded rect
            in_rect = True
            if x < corner and y < corner:
                dx = x - corner
                dy = y - corner
                if dx*dx + dy*dy > corner*corner:
                    in_rect = False
            if x >= s - corner and y < corner:
                dx = x - (s - corner - 1)
                dy = y - corner
                if dx*dx + dy*dy > corner*corner:
                    in_rect = False
            if in_rect:
                set_pixel(x, y, 255, 255, 255, alpha)

    # Document shape (white, slightly rounded)
    doc_left = s * 22 // 100
    doc_right = s * 78 // 100
    doc_top = s * 14 // 100
    doc_bottom = s * 86 // 100
    doc_corner = max(s // 30, 2)
    fold = s * 14 // 100  # folded corner size

    # Draw document body (white)
    fill_rounded_rect(doc_left, doc_top, doc_right, doc_bottom, doc_corner, 255, 255, 255, 240)

    # Folded corner (top-right): triangle shadow
    fold_x = doc_right - fold
    fold_y = doc_top
    for y in range(fold_y, fold_y + fold):
        for x in range(fold_x, doc_right):
            # Triangle: if x + y < fold_x + fold_y + fold -> in fold area
            if (x - fold_x) + (y - fold_y) < fold:
                set_pixel(x, y, 220, 230, 245, 200)  # lighter fold color

    # "M↓" Markdown symbol
    # Draw a bold "M" and down arrow
    cx = s // 2
    cy = s * 42 // 100

    # Draw "M" character - thick strokes
    m_width = s * 28 // 100
    m_height = s * 22 // 100
    m_thick = max(s * 5 // 100, 2)
    m_left = cx - m_width // 2
    m_top = cy - m_height // 2

    # Left vertical bar of M
    fill_rect(m_left, m_top, m_left + m_thick, m_top + m_height, 30, 100, 220)
    # Right vertical bar of M
    fill_rect(m_left + m_width - m_thick, m_top, m_left + m_width, m_top + m_height, 30, 100, 220)
    # Left diagonal of M
    for i in range(m_height // 2):
        x = m_left + m_thick + i * (m_width // 2 - m_thick) // (m_height // 2)
        y = m_top + i
        fill_rect(x, y, x + m_thick, y + max(2, m_thick//2), 30, 100, 220)
    # Right diagonal of M
    for i in range(m_height // 2):
        x = m_left + m_width - m_thick - i * (m_width // 2 - m_thick) // (m_height // 2)
        y = m_top + i
        fill_rect(x - m_thick + 1, y, x + 1, y + max(2, m_thick//2), 30, 100, 220)

    # Down arrow below M
    arrow_cy = s * 68 // 100
    arrow_w = s * 14 // 100
    arrow_h = s * 10 // 100
    arrow_thick = max(s * 4 // 100, 2)

    # Vertical line of arrow
    fill_rect(cx - arrow_thick // 2, arrow_cy - arrow_h, cx + arrow_thick // 2 + 1, arrow_cy, 30, 100, 220)
    # Arrow head (triangle)
    head_h = s * 7 // 100
    for row in range(head_h):
        half_w = arrow_w * row // head_h
        y = arrow_cy + row - head_h // 3
        fill_rect(cx - half_w, y, cx + half_w + 1, y + 1, 30, 100, 220)

    return pixels


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    iconset_dir = os.path.join(script_dir, 'AppIcon.iconset')
    os.makedirs(iconset_dir, exist_ok=True)

    # macOS icon sizes: 16, 32, 64, 128, 256, 512, 1024
    icon_sizes = [
        ('icon_16x16.png', 16),
        ('icon_16x16@2x.png', 32),
        ('icon_32x32.png', 32),
        ('icon_32x32@2x.png', 64),
        ('icon_128x128.png', 128),
        ('icon_128x128@2x.png', 256),
        ('icon_256x256.png', 256),
        ('icon_256x256@2x.png', 512),
        ('icon_512x512.png', 512),
        ('icon_512x512@2x.png', 1024),
    ]

    # Cache rendered icons by size
    cache = {}
    for filename, sz in icon_sizes:
        if sz not in cache:
            print(f'  Rendering {sz}x{sz}...', flush=True)
            cache[sz] = draw_icon(sz)
        png_data = create_png(sz, sz, cache[sz])
        filepath = os.path.join(iconset_dir, filename)
        with open(filepath, 'wb') as f:
            f.write(png_data)
        print(f'  Created {filename}', flush=True)

    print('Icon set created at:', iconset_dir, flush=True)


if __name__ == '__main__':
    main()
