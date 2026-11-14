pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Open windows, pinned dock apps and Trash state, via windows.py (which talks to KWin).
Singleton {
    id: root
    property var list: []      // open windows: [{id, title, app, appName, icon, active, minimized, ...}]
    property var pinned: []    // pinned apps: [{id, name, icon}]
    property bool trashFull: false
    property bool showingDesktop: false   // KDE's "Show Desktop" is on
    // True when you're looking at the desktop: Show Desktop is on, or no window
    // on the current virtual desktop is showing (all minimised, or none open).
    readonly property bool desktopVisible: showingDesktop
        || !list.some(w => !w.minimized && w.onCurrentDesktop !== false)

    // window actions
    function focus(id)    { bridge.write(`focus ${id}\n`) }
    function minimize(id) { bridge.write(`minimize ${id}\n`) }
    function maximize(id) { bridge.write(`maximize ${id}\n`) }   // toggles
    function close(id)    { bridge.write(`close ${id}\n`) }
    // app actions
    function launch(app)  { bridge.write(`launch ${app}\n`) }
    function toggleApp(app) { bridge.write(`toggleapp ${app}\n`) }   // minimise if in front, else bring forward
    function pin(app)     { bridge.write(`pin ${app}\n`) }
    function unpin(app)   { bridge.write(`unpin ${app}\n`) }
    function quit(app)    { for (const w of list) if (w.app === app) close(w.id) }
    function trash(cmd)   { bridge.write(`trash ${cmd}\n`) }   // "open" | "empty"
    // Do Not Disturb (held by windows.py; see set_dnd there).
    function setDnd(on)   { bridge.write(`dnd ${on ? "on" : "off"}\n`) }

    // For keyboard shortcuts:  qs ipc -p ~/Projects/taskbar call taskbar controlCenter
    //                          qs ipc -p ~/Projects/taskbar call taskbar controlCenterPage wifi
    IpcHandler {
        target: "taskbar"
        function controlCenter(): void { Menus.anchorX = 1e6; Menus.toggle("control", null) }   // top-right
        // page: "main", "wifi" or "bluetooth"
        function controlCenterPage(page: string): void { Menus.anchorX = 1e6; Menus.open = ""; Menus.toggle("control", null, page) }
    }

    // {windowId: [x, y, w, h]} of each dock icon on screen, for the minimise animation.
    function reportRects(map) { bridge.write(`rects ${JSON.stringify(map)}\n`) }

    Process {
        id: bridge
        command: ["python3", Qt.resolvedUrl("windows.py").toString().replace("file://", "")]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let msg
                try { msg = JSON.parse(line) } catch (e) { console.warn("windows.py:", line); return }
                if (msg.type === "windows") { root.list = msg.list; root.showingDesktop = msg.showingDesktop === true }
                else if (msg.type === "pinned") root.pinned = msg.apps
                else if (msg.type === "trash") root.trashFull = msg.full
            }
        }
        stderr: SplitParser { onRead: line => console.warn("windows.py:", line) }
        onExited: (code, status) => { console.warn("windows.py exited", code); restart.start() }
    }

    // If the bridge dies (e.g. KWin restarted), bring it back.
    Timer { id: restart; interval: 2000; onTriggered: bridge.running = true }
}
