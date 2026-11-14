#!/usr/bin/env python3
"""Bridge between KWin and the taskbar.

KDE doesn't offer the window-list protocol Quickshell understands, so:
  * a small KWin script (below) reports the window list over D-Bus to this
    process whenever it changes; this process prints it as one JSON line;
  * the taskbar writes commands to our stdin ("activate <id>", "close <id>"),
    which we carry out by running a one-shot KWin script;
  * the taskbar also writes "rects <json>" with each dock icon's screen position.
    We pass those to iconhelper/iconhelper, which tells KWin through Plasma's
    window-management protocol (so Magic Lamp / genie and Squash animate into
    the right icon), and also to the "Squash to Dock" effect via its config.

It also keeps the dock's pinned apps (dock.json), launches apps and watches
the Trash. Output is one JSON object per line:
  {"type": "windows", "list": [...]}   open windows
  {"type": "pinned",  "apps": [...]}   pinned apps with name + icon
  {"type": "trash",   "full": bool}

Run by Windows.qml; exits when the taskbar does (stdin closes).
"""
import functools
import itertools
import json
import os
import signal
import subprocess
import sys
import tempfile
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "local.taskbar.Windows"
OBJ_PATH = "/Windows"
# Unique per run: KWin won't reliably re-run a script loaded again under a name
# it has already used, which left the dock with no windows after restarts.
PLUGIN = f"taskbar-windows-{os.getpid()}"

IFACE_XML = f"""
<node>
  <interface name="{BUS_NAME}">
    <method name="Update"><arg type="s" name="json" direction="in"/></method>
  </interface>
</node>
"""

WATCH_SCRIPT = f"""
const SVC = "{BUS_NAME}", PATH = "{OBJ_PATH}";
function relevant(w) {{ return w.normalWindow && !w.skipTaskbar; }}
// Does this window currently have no title bar of its own? True only for
// windows KWin decorates (KDE title bars) that are maximised and borderless.
// Apps that draw their own title bars (Firefox, Electron) are excluded by
// remembering which windows/apps have ever shown a KDE title bar.
const kdeTitled = {{}};
function decorated(w) {{
  return w.decorationHasAlpha || (w.frameGeometry.height - w.clientGeometry.height) > 4;
}}
function titlebarless(w) {{
  const cls = w.resourceClass || "";
  if (decorated(w)) {{ w.tbKdeTitled = true; kdeTitled[cls] = true; }}
  const kde = w.tbKdeTitled || kdeTitled[cls] || cls.startsWith("org.kde.");
  return !!kde && w.maximizeMode === 3 && w.noBorder && !decorated(w);
}}
function info(w) {{
  return {{
    id: w.internalId.toString(),
    title: w.caption,
    appId: w.desktopFileName || "",
    cls: w.resourceClass || "",
    wclass: (w.resourceName || "") + " " + (w.resourceClass || ""),
    active: w === workspace.activeWindow,
    minimized: w.minimized,
    titlebarless: titlebarless(w),
    tempAbove: !!w.tbTempAbove && w.keepAbove,
    onCurrentDesktop: w.onAllDesktops || w.desktops.includes(workspace.currentDesktop),
  }};
}}
function push(gone) {{
  const list = workspace.windowList().filter(w => w !== gone && relevant(w)).map(info);
  callDBus(SVC, PATH, SVC, "Update", JSON.stringify({{ list: list, showingDesktop: workspace.showingDesktop }}));
}}
function watch(w) {{
  if (decorated(w)) {{ w.tbKdeTitled = true; kdeTitled[w.resourceClass || ""] = true; }}
  on(w, "captionChanged", () => push());
  // Workaround for KWin bug 528416: when a window minimises, the window that
  // gets focus next can be raised over it and hide the genie. Keep the
  // minimising window above while the genie plays; windows.py turns it off
  // ~1.5 s later (so a restart can never leave a window stuck on top).
  on(w, "minimizedChanged", () => {{
    if (w.minimized) {{
      if (!w.keepAbove) {{ w.tbTempAbove = true; w.keepAbove = true; }}
    }} else if (w.tbTempAbove) {{
      w.tbTempAbove = false; w.keepAbove = false;
    }}
    push();
  }});
  on(w, "maximizedChanged", () => push());
  on(w, "decorationChanged", () => push());
}}

// Connect only if the signal exists: a missing one throws and stops the whole script.
function on(obj, signal, fn) {{ if (obj && obj[signal] && obj[signal].connect) obj[signal].connect(fn); }}

workspace.windowList().forEach(watch);
on(workspace, "windowAdded", w => {{ watch(w); push(); }});
on(workspace, "windowRemoved", w => push(w));
on(workspace, "windowActivated", () => push());
on(workspace, "showingDesktopChanged", () => push());
on(workspace, "currentDesktopChanged", () => push());
push();
"""

ACTIONS = {
    # Click: focus it; if it's already focused, minimise it (like a normal taskbar).
    "activate": """
      if (workspace.activeWindow === w && !w.minimized) w.minimized = true;
      else { w.minimized = false; workspace.activeWindow = w; }
    """,
    "close": "w.closeWindow();",
    # Dock click (macOS style): bring forward, restoring it if minimised.
    "focus": "w.minimized = false; workspace.activeWindow = w;",
    "minimize": "w.minimized = true;",
    # Toggle maximised (KWin's own action works on the active window).
    "maximize": "workspace.activeWindow = w; workspace.slotWindowMaximize();",
}

EFFECT = "dockminimize"

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
windows_by_id = {}       # latest window list from KWin, by id
last_rects_json = None   # last value written to the effect's config
last_snapshot = ""       # last snapshot sent to iconhelper (resent if it restarts)
HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "iconhelper", "iconhelper")
helper = None


def send_to_helper(snapshot):
    """Send a full icon snapshot to iconhelper, (re)starting it if needed."""
    global helper
    if not os.access(HELPER, os.X_OK):
        return
    for _ in range(2):
        if helper is None or helper.poll() is not None:
            helper = subprocess.Popen([HELPER], stdin=subprocess.PIPE, text=True)
        try:
            helper.stdin.write(snapshot)
            helper.stdin.flush()
            return
        except (BrokenPipeError, OSError):
            helper = None
tmpdir = tempfile.mkdtemp(prefix="taskbar-windows-")
counter = itertools.count()


def kwin(method, sig, *args, path="/Scripting", iface="org.kde.kwin.Scripting"):
    return bus.call_sync("org.kde.KWin", path, iface, method,
                         GLib.Variant(sig, args) if sig else None,
                         None, Gio.DBusCallFlags.NONE, -1, None).unpack()


def run_script(source, name):
    """Load a KWin script from a string and start it. Returns nothing; KWin owns it."""
    path = os.path.join(tmpdir, name + ".js")
    with open(path, "w") as f:
        f.write(source)
    kwin("unloadScript", "(s)", name)
    (sid,) = kwin("loadScript", "(ss)", path, name)
    if sid < 0:
        print(f"kwin refused to load {name}", file=sys.stderr, flush=True)
        return
    # Start it with Scripting.start() (runs every loaded, not-yet-running script)
    # rather than /Scripting/Script<id>.run(): KWin reuses ids, and after scripts
    # have been unloaded that path can still point at an old, dead script.
    kwin("start", None)


def do_action(action, wid):
    body = ACTIONS.get(action)
    if body is None or not wid.startswith("{"):
        return
    name = f"taskbar-act-{next(counter)}"
    src = f'const w = workspace.windowList().find(x => x.internalId.toString() === {wid!r});\nif (w) {{ {body} }}\n'
    run_script(src, name)
    # One-shot: unload shortly after it has run.
    GLib.timeout_add(1000, lambda: (kwin("unloadScript", "(s)", name), False)[1])


def desktop_info(app_id):
    """Gio.DesktopAppInfo for '<app_id>.desktop', or None. (PyGObject raises
    TypeError instead of returning None when there's no such file.)"""
    if not app_id:
        return None
    try:
        return Gio.DesktopAppInfo.new(app_id + ".desktop")
    except TypeError:
        return None


@functools.lru_cache(maxsize=256)
def icon_for(app_id, cls):
    """Icon name (or file path) from the app's .desktop file, guessing like a taskbar would."""
    for cand in (app_id, cls, cls.lower()):
        if not cand:
            continue
        info = desktop_info(cand)
        icon = info.get_icon() if info else None
        if icon:
            return icon.to_string()
    return (app_id or cls).lower()


def set_rects(payload):
    """Map dock icon rects (by window id) to the keys the effect can see, and
    store them in the effect's config if they changed."""
    global last_rects_json
    global last_snapshot
    rects = {}
    lines = []
    for wid, rect in json.loads(payload).items():
        w = windows_by_id.get(wid)
        if not w or len(rect) != 4:
            continue
        rect = [round(v) for v in rect]
        rects[w["wclass"] + "\n" + w["title"]] = rect
        rects.setdefault(w["wclass"], rect)   # fallback if the title changed
        lines.append(f"{wid} {rect[0]} {rect[1]} {rect[2]} {rect[3]}\n")
    snapshot = "".join(sorted(lines)) + "end\n"
    if snapshot != last_snapshot:
        last_snapshot = snapshot
        send_to_helper(snapshot)
    out = json.dumps(rects, sort_keys=True)
    if out == last_rects_json:
        return
    last_rects_json = out
    subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", f"Effect-{EFFECT}",
                    "--key", "IconRects", out], check=False)
    try:
        bus.call_sync("org.kde.KWin", "/Effects", "org.kde.kwin.Effects", "reconfigureEffect",
                      GLib.Variant("(s)", (EFFECT,)), None, Gio.DBusCallFlags.NONE, -1, None)
    except GLib.Error:
        pass   # effect not loaded; harmless


# Do Not Disturb: the notification server keeps an inhibit only while the
# caller's D-Bus connection lives, so this long-running process holds it.
dnd_cookie = None


def set_dnd(on):
    global dnd_cookie
    try:
        if on and dnd_cookie is None:
            (dnd_cookie,) = bus.call_sync(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                "org.freedesktop.Notifications", "Inhibit",
                GLib.Variant("(ssa{sv})", ("org.quickshell", "Do Not Disturb", {})),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None).unpack()
        elif not on and dnd_cookie is not None:
            bus.call_sync("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                          "org.freedesktop.Notifications", "UnInhibit", GLib.Variant("(u)", (dnd_cookie,)),
                          None, Gio.DBusCallFlags.NONE, -1, None)
            dnd_cookie = None
    except GLib.Error as e:
        print(f"do not disturb failed: {e.message}", file=sys.stderr, flush=True)


def toggle_app(app):
    """Dock click on a running app. Decided inside KWin with its live state, so
    rapid clicks each toggle exactly once, in order:
      in front  -> minimise all its windows
      otherwise -> bring its topmost window forward (restoring all if all were minimised)"""
    ids = [w["id"] for w in windows_by_id.values() if w.get("app") == app]
    if not ids:
        return
    name = f"taskbar-toggle-{next(counter)}"
    src = f"""
const ids = {json.dumps(ids)};
const ws = workspace.stackingOrder.filter(w => ids.includes(w.internalId.toString()));  // bottom -> top
if (ws.length) {{
  const front = ws.some(w => w === workspace.activeWindow && !w.minimized);
  if (front) {{
    ws.forEach(w => w.minimized = true);
  }} else {{
    const visible = ws.filter(w => !w.minimized);
    if (visible.length === 0) ws.forEach(w => w.minimized = false);
    workspace.activeWindow = (visible.length ? visible : ws)[(visible.length ? visible : ws).length - 1];
  }}
}}
"""
    run_script(src, name)
    GLib.timeout_add(1000, lambda: (kwin("unloadScript", "(s)", name), False)[1])


# ---------- keep-above workaround cleanup ----------
# The KWin script keeps a minimising window "above" so the genie isn't hidden
# (KWin bug 528416). It's only needed during the animation, so turn it off
# shortly after; otherwise a taskbar restart could leave windows stuck on top
# (which once hid the dock's bottom-edge trigger behind a full-screen window).
temp_above_pending = set()


def clear_temp_above(wid):
    temp_above_pending.discard(wid)
    name = f"taskbar-unabove-{next(counter)}"
    run_script(f"""
const w = workspace.windowList().find(x => x.internalId.toString() === {json.dumps(wid)});
if (w && w.minimized && w.keepAbove && w.tbTempAbove !== false) w.keepAbove = false;
""", name)
    GLib.timeout_add(1000, lambda: (kwin("unloadScript", "(s)", name), False)[1])
    return False


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def app_key(app_id, cls):
    """The id the dock groups windows by: the .desktop name when known."""
    for cand in (app_id, cls, cls.lower()):
        if cand and desktop_info(cand):
            return cand
    return (app_id or cls)


@functools.lru_cache(maxsize=256)
def app_info(app):
    info = desktop_info(app)
    if not info:
        return {"id": app, "name": app, "icon": app.lower()}
    icon = info.get_icon()
    return {"id": app, "name": info.get_name() or app, "icon": icon.to_string() if icon else app.lower()}


# ---------- pinned apps (dock.json) ----------
DOCK_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dock.json")
DEFAULT_PINS = ["org.kde.dolphin", "firefox", "com.anthropic.Claude", "org.kde.konsole",
                "org.kde.kate", "systemsettings"]


def load_pins():
    try:
        with open(DOCK_FILE) as f:
            return [p for p in json.load(f).get("pinned", []) if isinstance(p, str)]
    except (OSError, ValueError):
        return [p for p in DEFAULT_PINS if desktop_info(p)]


pins = load_pins()


def save_and_emit_pins():
    with open(DOCK_FILE, "w") as f:
        json.dump({"pinned": pins}, f, indent=2)
        f.write("\n")
    emit({"type": "pinned", "apps": [app_info(p) for p in pins]})


def pin(app, on):
    if on and app not in pins:
        pins.append(app)
    elif not on and app in pins:
        pins.remove(app)
    save_and_emit_pins()


def launch(app):
    """Start an app in its own systemd scope (like KDE does). Launching it
    directly would put it inside the taskbar's service, so restarting the
    taskbar would kill the app too - which is how Firefox kept dying."""
    if not desktop_info(app):
        return
    safe = "".join(c if c.isalnum() else "_" for c in app)
    subprocess.Popen(["systemd-run", "--user", "--scope", "--collect", "--quiet",
                      "--slice=app.slice", f"--unit=app-{safe}-{os.getpid()}-{next(counter)}",
                      "gtk-launch", app],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


# ---------- Trash ----------
TRASH = Gio.File.new_for_path(os.path.expanduser("~/.local/share/Trash/files"))
trash_monitor = None


def trash_full():
    try:
        it = TRASH.enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, None)
        return it.next_file(None) is not None
    except GLib.Error:
        return False


def emit_trash(*_):
    emit({"type": "trash", "full": trash_full()})


def trash(cmd):
    if cmd == "open":
        subprocess.Popen(["dolphin", "trash:/"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif cmd == "empty":
        subprocess.run(["ktrash6", "--empty"], check=False)
        emit_trash()


def on_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "Update":
        data = json.loads(params.unpack()[0])
        # {list, showingDesktop} from the KWin script (a bare list from older versions)
        windows = data["list"] if isinstance(data, dict) else data
        showing_desktop = bool(data.get("showingDesktop")) if isinstance(data, dict) else False
        for w in windows:
            w["icon"] = icon_for(w.get("appId", ""), w.get("cls", ""))
            w["app"] = app_key(w.get("appId", ""), w.get("cls", ""))
            w["appName"] = app_info(w["app"])["name"]
        windows_by_id.clear()
        windows_by_id.update({w["id"]: w for w in windows})
        for w in windows:
            if w.get("tempAbove") and w.get("minimized") and w["id"] not in temp_above_pending:
                temp_above_pending.add(w["id"])
                GLib.timeout_add(1500, clear_temp_above, w["id"])
        emit({"type": "windows", "list": windows, "showingDesktop": showing_desktop})
    invocation.return_value(None)


def on_stdin(source, condition):
    if condition & (GLib.IO_HUP | GLib.IO_ERR):
        loop.quit()
        return False
    line = source.readline()
    if not line:
        loop.quit()
        return False
    parts = line.strip().split(" ", 1)
    if len(parts) == 2:
        try:
            if parts[0] == "rects":
                set_rects(parts[1])
            elif parts[0] == "dnd":
                set_dnd(parts[1] == "on")
            elif parts[0] == "launch":
                launch(parts[1])
            elif parts[0] == "toggleapp":
                toggle_app(parts[1])
            elif parts[0] == "pin":
                pin(parts[1], True)
            elif parts[0] == "unpin":
                pin(parts[1], False)
            elif parts[0] == "trash":
                trash(parts[1])
            else:
                do_action(*parts)
        except (GLib.Error, ValueError, KeyError) as e:
            print(f"command failed: {e}", file=sys.stderr, flush=True)
    return True


def cleanup():
    try:
        kwin("unloadScript", "(s)", PLUGIN)
    except GLib.Error:
        pass
    if helper is not None and helper.poll() is None:
        helper.terminate()
    set_dnd(False)


loop = GLib.MainLoop()
node = Gio.DBusNodeInfo.new_for_xml(IFACE_XML)
bus.register_object(OBJ_PATH, node.interfaces[0], on_call, None, None)


def on_name_acquired(*_):
    global trash_monitor
    try:
        kwin("unloadScript", "(s)", "taskbar-windows")   # the old fixed name, from earlier versions
    except GLib.Error:
        pass
    # Start the KWin watcher once our main loop is running and the D-Bus object
    # can answer it; started from inside this callback it never got going.
    GLib.timeout_add(150, lambda: (run_script(WATCH_SCRIPT, PLUGIN), False)[1])
    save_and_emit_pins()
    try:
        trash_monitor = TRASH.monitor_directory(Gio.FileMonitorFlags.NONE, None)
        trash_monitor.connect("changed", emit_trash)
    except GLib.Error:
        pass
    emit_trash()


def on_name_lost(*_):
    print(f"could not own {BUS_NAME} (another taskbar running?)", file=sys.stderr, flush=True)
    loop.quit()


Gio.bus_own_name_on_connection(bus, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
                               on_name_acquired, on_name_lost)

stdin = GLib.IOChannel.unix_new(sys.stdin.fileno())
GLib.io_add_watch(stdin, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
for sig in (signal.SIGTERM, signal.SIGINT):
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])

try:
    loop.run()
finally:
    cleanup()
