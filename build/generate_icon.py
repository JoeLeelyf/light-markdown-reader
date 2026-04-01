#!/usr/bin/env python3
"""Generate fview app icon set from source PNG using sips."""
import os
import subprocess
import shutil

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source = os.path.join(script_dir, 'icon_source.png')
    iconset_dir = os.path.join(script_dir, 'AppIcon.iconset')

    if not os.path.exists(source):
        print(f'Error: {source} not found')
        raise SystemExit(1)

    # Clean and recreate iconset directory
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir)

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

    # First convert source to proper PNG with alpha channel
    canonical = os.path.join(iconset_dir, '_source.png')
    shutil.copy2(source, canonical)
    subprocess.run(
        ['sips', '-s', 'format', 'png', '-s', 'dpiWidth', '72.0',
         '-s', 'dpiHeight', '72.0', canonical],
        capture_output=True, check=True
    )

    for filename, sz in icon_sizes:
        filepath = os.path.join(iconset_dir, filename)
        shutil.copy2(canonical, filepath)
        subprocess.run(
            ['sips', '-z', str(sz), str(sz), filepath],
            capture_output=True, check=True
        )
        print(f'  Created {filename} ({sz}x{sz})', flush=True)

    os.remove(canonical)

    print('Icon set created at:', iconset_dir, flush=True)


if __name__ == '__main__':
    main()
