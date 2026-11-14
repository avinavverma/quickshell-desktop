#!/usr/bin/env python3
"""Find the white title bars of the dialog boxes in the wallpaper.
Usage: detect.py <gray 960x540 raw> -> prints candidate rects at full (3840x2160) scale."""
import sys, json
W, H, K = 960, 540, 4
px = open(sys.argv[1], 'rb').read()
bright = bytearray(1 if v > 215 else 0 for v in px)
seen = bytearray(W * H)
out = []
for start in range(W * H):
    if not bright[start] or seen[start]:
        continue
    stack = [start]; seen[start] = 1
    x0 = y0 = 10**9; x1 = y1 = -1; n = 0
    while stack:
        i = stack.pop(); n += 1
        x, y = i % W, i // W
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        for j in (i - 1, i + 1, i - W, i + W):
            if 0 <= j < W * H and bright[j] and not seen[j] and abs(j % W - x) <= 1:
                seen[j] = 1; stack.append(j)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    if w >= 35 and 3 <= h <= 20 and w / h > 4 and n > 0.6 * w * h:
        out.append([x0 * K, y0 * K, w * K, h * K, n])
for r in sorted(out, key=lambda r: (r[1], r[0])):
    print(r)
