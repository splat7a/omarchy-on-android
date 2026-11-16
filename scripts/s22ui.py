#!/usr/bin/env python3
"""Tiny UI driver for the S22 phone screen over adb (uiautomator dump + input tap).
   s22ui.py list                 show visible elements (text / desc / id / bounds)
   s22ui.py tap TEXT [N]         tap the N-th element whose text, desc or id contains TEXT
   s22ui.py tapxy X Y            tap a coordinate
   s22ui.py shot FILE            screenshot of the phone screen (scaled copy FILE-small.png)"""
import re, subprocess, sys, time

T = 's22:5555'
PHONE = '4630947232161729154'   # SurfaceFlinger id of the built-in screen

def adb(*a, out=True):
    return subprocess.run(['timeout', '60', 'adb', '-s', T, *a], capture_output=out, text=True).stdout

def nodes():
    adb('shell', 'uiautomator dump /sdcard/Download/ui.xml >/dev/null 2>&1')
    x = adb('shell', 'cat /sdcard/Download/ui.xml')
    res = []
    for m in re.finditer(r'<node ([^>]*?)/?>', x):
        a = dict(re.findall(r'(\S+?)="([^"]*)"', m.group(1)))
        b = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', a.get('bounds', ''))
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        res.append(dict(text=a.get('text', ''), desc=a.get('content-desc', ''), id=a.get('resource-id', ''),
                        cls=a.get('class', '').split('.')[-1], checked=a.get('checked'), clickable=a.get('clickable'),
                        cx=(x1 + x2) // 2, cy=(y1 + y2) // 2, bounds=(x1, y1, x2, y2)))
    return res

def main():
    cmd = sys.argv[1]
    if cmd == 'list':
        for n in nodes():
            if n['text'] or n['desc'] or (n['clickable'] == 'true' and n['id']):
                print(f"{n['text'][:50]!r:52} desc={n['desc'][:30]!r:32} {n['cls']:14} chk={n['checked']} @({n['cx']},{n['cy']}) id={n['id'].split('/')[-1]}")
    elif cmd == 'tap':
        want, idx = sys.argv[2].lower(), int(sys.argv[3]) if len(sys.argv) > 3 else 0
        hits = [n for n in nodes() if want in n['text'].lower() or want in n['desc'].lower() or want in n['id'].lower()]
        if len(hits) <= idx:
            sys.exit(f'not found: {sys.argv[2]}')
        n = hits[idx]
        adb('shell', f"input tap {n['cx']} {n['cy']}")
        print(f"tapped {n['text'] or n['desc'] or n['id']!r} at ({n['cx']},{n['cy']})")
        time.sleep(1.5)
    elif cmd == 'tapxy':
        adb('shell', f'input tap {sys.argv[2]} {sys.argv[3]}')
        time.sleep(1.5)
    elif cmd == 'shot':
        png = subprocess.run(['timeout', '60', 'adb', '-s', T, 'exec-out', 'screencap', '-d', PHONE, '-p'], capture_output=True).stdout
        open(sys.argv[2], 'wb').write(png)
        subprocess.run(['magick', sys.argv[2], '-resize', '30%', sys.argv[2].replace('.png', '-small.png')])
        print(sys.argv[2].replace('.png', '-small.png'))

if __name__ == '__main__':
    main()
