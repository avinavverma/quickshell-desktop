#!/usr/bin/env python3
"""Testing helper: where is the mouse pointer? Takes two spectacle shots (with and
without the pointer) and prints the top-left of the pixels that differ: "x y"."""
import subprocess, sys, tempfile, os, time
d = tempfile.mkdtemp()
a, b = os.path.join(d, 'a.png'), os.path.join(d, 'b.png')
subprocess.run(['spectacle', '-b', '-n', '-f', '-o', a]); time.sleep(1.2)
subprocess.run(['spectacle', '-b', '-n', '-f', '-p', '-o', b]); time.sleep(1.2)
def raw(p):
    return subprocess.run(['ffmpeg', '-v', 'error', '-i', p, '-f', 'rawvideo', '-pix_fmt', 'gray', '-'],
                          capture_output=True).stdout
A, B = raw(a), raw(b)
W = 1920
idx = [i for i in range(len(A)) if abs(A[i] - B[i]) > 40]
if not idx: print('none'); sys.exit(1)
xs=[i % W for i in idx]; ys=[i // W for i in idx]
print(min(xs), min(ys), max(xs), max(ys), len(idx))
