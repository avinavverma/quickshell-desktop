#!/usr/bin/env python3
"""Watch the touchpad for a four-finger tap and print "tap4" for each one.

KDE/libinput does nothing with four-finger taps (taps only go up to three fingers, which is the
middle click), so this adds no side effects. The touchpad is read directly from evdev, without
grabbing it - KWin keeps getting every event as usual. Needs read access to /dev/input/event*
(the "input" group).

A tap = four fingers on (BTN_TOOL_QUADTAP) for at most MAX_DOWN seconds, barely moving, and all
fingers off again (BTN_TOUCH 0) within LIFT seconds after that - so a four-finger swipe or a
four-finger rest that turns into something else doesn't count.
"""
import fcntl, os, select, struct, sys, time

EV_KEY, EV_ABS = 0x01, 0x03
ABS_X, ABS_Y = 0x00, 0x01
BTN_LEFT, BTN_TOUCH, BTN_TOOL_QUADTAP, BTN_TOOL_QUINTTAP = 0x110, 0x14A, 0x14F, 0x148
EVENT = struct.Struct("llHHi")          # struct input_event on 64-bit
MAX_DOWN = 0.35                        # seconds with four fingers on
LIFT = 0.30                            # seconds to lift the rest after that
MOVE_FRACTION = 0.05                   # allowed movement, fraction of the pad's width


def find_touchpad():
    with open("/proc/bus/input/devices") as f:
        for block in f.read().split("\n\n"):
            if "Touchpad" in block or "touchpad" in block:
                for line in block.splitlines():
                    if line.startswith("H: Handlers="):
                        for h in line.split("=", 1)[1].split():
                            if h.startswith("event"):
                                return "/dev/input/" + h
    return None


def abs_range(fd, axis):
    # EVIOCGABS(axis) = _IOR('E', 0x40 + axis, struct input_absinfo) ; input_absinfo = 6 x int32
    buf = bytearray(24)
    req = (2 << 30) | (24 << 16) | (ord("E") << 8) | (0x40 + axis)
    try:
        fcntl.ioctl(fd, req, buf)
        _, lo, hi, *_ = struct.unpack("6i", buf)
        return max(1, hi - lo)
    except OSError:
        return 3000


class Detector:
    def __init__(self, limit):
        self.limit = limit
        self.down_at = None        # when four fingers went down
        self.candidate_at = None   # when four fingers went up (waiting for all fingers to lift)
        self.x = self.y = self.x0 = self.y0 = None
        self.moved = 0.0
        self.clicked = False

    def feed(self, etype, code, value, now):
        """One evdev event; returns True when a four-finger tap is complete."""
        if etype == EV_ABS and code in (ABS_X, ABS_Y):
            if code == ABS_X: self.x = value
            else: self.y = value
            if self.down_at is not None or self.candidate_at is not None:
                if self.x0 is None: self.x0 = self.x
                if self.y0 is None: self.y0 = self.y
                if None not in (self.x, self.y, self.x0, self.y0):
                    self.moved = max(self.moved, abs(self.x - self.x0) + abs(self.y - self.y0))
        elif etype == EV_KEY:
            if code == BTN_LEFT and value:
                self.clicked = True
            elif code == BTN_TOOL_QUINTTAP and value:
                self.down_at = self.candidate_at = None          # five fingers: not ours
            elif code == BTN_TOOL_QUADTAP:
                if value:
                    self.down_at, self.moved, self.clicked, self.candidate_at = now, 0.0, False, None
                    self.x0, self.y0 = self.x, self.y
                elif self.down_at is not None:
                    if now - self.down_at <= MAX_DOWN and self.moved <= self.limit and not self.clicked:
                        self.candidate_at = now
                    self.down_at = None
            elif code == BTN_TOUCH and value == 0 and self.candidate_at is not None:
                ok = now - self.candidate_at <= LIFT and self.moved <= self.limit and not self.clicked
                self.candidate_at = None
                return ok
        return False


def main():
    path = os.environ.get("TOUCHPAD_DEVICE") or find_touchpad()
    if not path:
        print("no touchpad found", file=sys.stderr)
        return 2
    fd = os.open(path, os.O_RDONLY)
    det = Detector(abs_range(fd, ABS_X) * MOVE_FRACTION)
    while True:
        r, _, _ = select.select([fd], [], [], 1.0)
        if not r:
            continue
        data = os.read(fd, EVENT.size * 64)
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            _, _, etype, code, value = EVENT.unpack_from(data, i)
            if det.feed(etype, code, value, time.monotonic()):
                print("tap4", flush=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        pass
