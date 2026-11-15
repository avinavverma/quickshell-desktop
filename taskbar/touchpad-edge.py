#!/usr/bin/env python3
"""Left-edge media control for the touchpad.

    tap the left edge            -> prints "playpause"
    slide up / down on the edge  -> prints "vol +0.0300" / "vol -0.0300" (relative steps)
    four-finger tap (--tap4)     -> prints "tap4"

How: the real touchpad is grabbed (EVIOCGRAB, so KDE stops reading it directly) and an identical
virtual touchpad is created with uinput (same name, vendor/product, bus, axes and properties, so
KDE applies the same touchpad settings to it). Every touch is copied to the virtual touchpad
except one-finger touches that START in the left-edge strip: those are kept here, so they never
click, move the pointer or scroll. If this program stops or crashes, the grab and the virtual
touchpad go away with it and KDE uses the real touchpad again.

Needs read access to /dev/input/event* and write access to /dev/uinput (the "input" group).
Set TOUCHPAD_DEVICE=/dev/input/eventN to choose the device (used by the tests).
"""
import fcntl, os, select, struct, sys, time

# ---- evdev / uinput constants ----
EV_SYN, EV_KEY, EV_ABS, EV_MSC = 0x00, 0x01, 0x03, 0x04
SYN_REPORT = 0
ABS_X, ABS_Y, ABS_PRESSURE = 0x00, 0x01, 0x18
ABS_MT_SLOT, ABS_MT_TRACKING_ID = 0x2F, 0x39
ABS_MT_FIRST, ABS_MT_LAST = 0x2F, 0x3D
BTN_LEFT, BTN_TOUCH = 0x110, 0x14A
BTN_TOOL_FINGER, BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP = 0x145, 0x14D, 0x14E
BTN_TOOL_QUADTAP, BTN_TOOL_QUINTTAP = 0x14F, 0x148
MULTI = (BTN_TOOL_DOUBLETAP, BTN_TOOL_TRIPLETAP, BTN_TOOL_QUADTAP, BTN_TOOL_QUINTTAP)

EDGE_MM = 8.0          # width of the left strip
TAP_MAX_S = 0.30       # a tap is short ...
TAP_MOVE_MM = 2.5      # ... and barely moves
STEP_MM = 3.0          # every 3 mm of sliding = one volume step
STEP = 0.03            # volume per step (3 %)

EVENT = struct.Struct("llHHi")


def IOC(d, t, nr, size): return (d << 30) | (size << 16) | (ord(t) << 8) | nr
R, W = 2, 1
def EVIOCGBIT(ev, n): return IOC(R, "E", 0x20 + ev, n)
def EVIOCGABS(a): return IOC(R, "E", 0x40 + a, 24)
def EVIOCGPROP(n): return IOC(R, "E", 0x09, n)
def EVIOCGNAME(n): return IOC(R, "E", 0x06, n)
EVIOCGID = IOC(R, "E", 0x02, 8)
EVIOCGRAB = IOC(W, "E", 0x90, 4)
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = IOC(W, "U", 100, 4), IOC(W, "U", 101, 4), IOC(W, "U", 103, 4)
UI_SET_MSCBIT, UI_SET_PROPBIT = IOC(W, "U", 104, 4), IOC(W, "U", 110, 4)
UI_DEV_SETUP, UI_ABS_SETUP = IOC(W, "U", 3, 92), IOC(W, "U", 4, 28)
UI_DEV_CREATE, UI_DEV_DESTROY = IOC(0, "U", 1, 0), IOC(0, "U", 2, 0)


def bits(fd, req, nbits):
    buf = bytearray((nbits + 7) // 8)
    try:
        fcntl.ioctl(fd, req, buf)
    except OSError:
        return []
    return [i for i in range(nbits) if buf[i // 8] >> (i % 8) & 1]


def absinfo(fd, axis):
    buf = bytearray(24)
    fcntl.ioctl(fd, EVIOCGABS(axis), buf)
    return list(struct.unpack("6i", buf))      # value, min, max, fuzz, flat, resolution


def find_touchpad():
    with open("/proc/bus/input/devices") as f:
        for block in f.read().split("\n\n"):
            if "touchpad" in block.lower() and "Vendor=0000" not in block:
                name = ""
                for line in block.splitlines():
                    if line.startswith("N: Name="):
                        name = line
                    if line.startswith("H: Handlers="):
                        for h in line.split("=", 1)[1].split():
                            if h.startswith("event"):
                                return "/dev/input/" + h
    return None


def make_clone(src):
    """A uinput device that looks exactly like `src`."""
    ui = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    for ev in bits(src, EVIOCGBIT(0, 4), 32):
        fcntl.ioctl(ui, UI_SET_EVBIT, ev)
    for k in bits(src, EVIOCGBIT(EV_KEY, 96), 768):
        fcntl.ioctl(ui, UI_SET_KEYBIT, k)
    for a in bits(src, EVIOCGBIT(EV_ABS, 8), 64):
        fcntl.ioctl(ui, UI_SET_ABSBIT, a)
        info = absinfo(src, a)
        fcntl.ioctl(ui, UI_ABS_SETUP, struct.pack("HH6i", a, 0, *info))
    for m in bits(src, EVIOCGBIT(EV_MSC, 1), 8):
        fcntl.ioctl(ui, UI_SET_MSCBIT, m)
    for p in bits(src, EVIOCGPROP(4), 32):
        fcntl.ioctl(ui, UI_SET_PROPBIT, p)
    idbuf = bytearray(8); fcntl.ioctl(src, EVIOCGID, idbuf)
    bus, vendor, product, version = struct.unpack("4H", idbuf)
    namebuf = bytearray(256); fcntl.ioctl(src, EVIOCGNAME(256), namebuf)
    name = bytes(namebuf).split(b"\0", 1)[0][:79]
    fcntl.ioctl(ui, UI_DEV_SETUP, struct.pack("4H80sI", bus, vendor, product, version, name, 0))
    fcntl.ioctl(ui, UI_DEV_CREATE)
    return ui


class Filter:
    """Decides, frame by frame (SYN_REPORT to SYN_REPORT), what to pass on and what to keep."""

    def __init__(self, x_min, x_max, res_x, res_y, out, emit, tap4=None):
        rx = res_x or max(1, (x_max - x_min) // 100)
        ry = res_y or rx
        self.edge_x = x_min + EDGE_MM * rx
        self.tap_move = TAP_MOVE_MM * max(rx, ry)
        self.step = STEP_MM * ry
        self.out, self.emit, self.tap4 = out, emit, tap4
        # what the kernel says right now
        self.slot = 0
        self.mt = {}            # slot -> {code: value}
        self.st = {}            # single-touch axes: ABS_X, ABS_Y, ABS_PRESSURE ...
        self.keys = {}
        # what the virtual touchpad has been told
        self.fwd_slot = 0
        # an edge touch in progress
        self.edge = None        # {t0, x0, y0, last_y, acc, moved}

    def fingers(self):
        if any(self.keys.get(k) for k in MULTI):
            return 2
        return 1 if self.keys.get(BTN_TOOL_FINGER) else 0

    def frame(self, events, now):
        was_touching = bool(self.keys.get(BTN_TOUCH))
        # 1. update our copy of the kernel state, remembering the slot each MT event belongs to
        tagged = []
        slot = self.slot
        for (t, c, v) in events:
            if t == EV_ABS:
                if c == ABS_MT_SLOT:
                    slot = v
                elif ABS_MT_FIRST <= c <= ABS_MT_LAST:
                    self.mt.setdefault(slot, {})[c] = v
                else:
                    self.st[c] = v
            elif t == EV_KEY:
                self.keys[c] = v
            tagged.append((t, c, v, slot))
            if self.tap4 and self.tap4.feed(t, c, v, now):
                self.emit("tap4")
        self.slot = slot
        touching = bool(self.keys.get(BTN_TOUCH))

        # 2. an edge touch: keep everything until every finger is off
        if self.edge is not None:
            y = self.st.get(ABS_Y, self.edge["last_y"])
            x = self.st.get(ABS_X, self.edge["x0"])
            self.edge["moved"] = max(self.edge["moved"], abs(x - self.edge["x0"]) + abs(y - self.edge["y0"]))
            if self.fingers() <= 1 and not self.keys.get(BTN_LEFT):
                self.edge["acc"] += self.edge["last_y"] - y          # up = louder
                while self.edge["acc"] >= self.step:
                    self.emit("vol +%.4f" % STEP); self.edge["acc"] -= self.step; self.edge["slid"] = True
                while self.edge["acc"] <= -self.step:
                    self.emit("vol -%.4f" % STEP); self.edge["acc"] += self.step; self.edge["slid"] = True
            self.edge["last_y"] = y
            if not touching:
                e = self.edge
                if not e["slid"] and now - e["t0"] <= TAP_MAX_S and e["moved"] <= self.tap_move:
                    self.emit("playpause")
                self.edge = None
            return

        # 3. a new one-finger touch that starts in the left strip becomes an edge touch
        if touching and not was_touching and self.fingers() == 1 \
                and self.st.get(ABS_X, 1 << 30) < self.edge_x and not self.keys.get(BTN_LEFT):
            y = self.st.get(ABS_Y, 0)
            self.edge = {"t0": now, "x0": self.st[ABS_X], "y0": y, "last_y": y, "acc": 0, "moved": 0, "slid": False}
            return

        # 4. pass the frame on (fixing up the slot, and repeating the full position of any
        #    contact that starts now, because the kernel only sends values that changed)
        new_slots = set()
        for (t, c, v, s) in tagged:
            if t == EV_SYN:
                continue
            if t == EV_ABS and c == ABS_MT_SLOT:
                self.out(t, c, v); self.fwd_slot = v
                continue
            if t == EV_ABS and ABS_MT_FIRST <= c <= ABS_MT_LAST:
                if self.fwd_slot != s:
                    self.out(EV_ABS, ABS_MT_SLOT, s); self.fwd_slot = s
                if c == ABS_MT_TRACKING_ID and v >= 0:
                    new_slots.add(s)
            self.out(t, c, v)
        for s in sorted(new_slots):
            if self.fwd_slot != s:
                self.out(EV_ABS, ABS_MT_SLOT, s); self.fwd_slot = s
            for c, v in sorted(self.mt.get(s, {}).items()):
                if c != ABS_MT_TRACKING_ID:
                    self.out(EV_ABS, c, v)
        if touching and not was_touching:
            for c, v in sorted(self.st.items()):
                self.out(EV_ABS, c, v)
        self.out(EV_SYN, SYN_REPORT, 0)


def main():
    tap4 = None
    if "--tap4" in sys.argv:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import importlib.util
        spec = importlib.util.spec_from_file_location("taps", os.path.join(os.path.dirname(os.path.abspath(__file__)), "touchpad-taps.py"))
        taps = importlib.util.module_from_spec(spec); spec.loader.exec_module(taps)
    path = os.environ.get("TOUCHPAD_DEVICE") or find_touchpad()
    if not path:
        print("no touchpad found", file=sys.stderr)
        return 2
    src = os.open(path, os.O_RDONLY)
    ix, iy = absinfo(src, ABS_X), absinfo(src, ABS_Y)
    if "--tap4" in sys.argv:
        tap4 = taps.Detector((ix[2] - ix[1]) * taps.MOVE_FRACTION)
    ui = make_clone(src)
    time.sleep(0.2)                       # let the virtual touchpad appear before taking the real one
    fcntl.ioctl(src, EVIOCGRAB, 1)

    def out(t, c, v):
        os.write(ui, EVENT.pack(0, 0, t, c, v))

    def emit(line):
        print(line, flush=True)

    flt = Filter(ix[1], ix[2], ix[5], iy[5], out, emit, tap4)
    pending = []
    try:
        while True:
            r, _, _ = select.select([src], [], [], 1.0)
            if not r:
                continue
            data = os.read(src, EVENT.size * 64)
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, t, c, v = EVENT.unpack_from(data, i)
                if t == EV_SYN and c == SYN_REPORT:
                    flt.frame(pending, time.monotonic()); pending = []
                else:
                    pending.append((t, c, v))
    finally:
        try: fcntl.ioctl(src, EVIOCGRAB, 0)
        except OSError: pass
        try: fcntl.ioctl(ui, UI_DEV_DESTROY)
        except OSError: pass


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        pass
