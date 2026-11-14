import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// The macOS-style dock row: launcher, pinned + running apps, divider,
// minimised windows (one tile each, in the order they were minimised), Trash.
//  - one icon per app; a dot under running apps
//  - click: launch (icon bounces until a window shows up), bring the app
//    forward, or — if it's the app in front — minimise it. Scroll cycles windows.
//  - middle click: new instance. Right click: menu (windows, Keep in Dock, Quit).
//  - optional hover magnification (Theme.dockMagnify; off by default, like macOS).
//  - icons dim while pressed.
RowLayout {
    id: root
    readonly property var win: QsWindow.window
    readonly property var enabledIds: Modules.ids("Dock")
    readonly property bool available: true
    spacing: 0

    // ---------- the items ----------
    readonly property var entries: {
        const out = []
        if (enabledIds.includes("launcher")) out.push({ kind: "launcher", key: "launcher", name: "Applications" })
        if (enabledIds.includes("tasks")) {
            const byApp = {}
            for (const w of Windows.list) (byApp[w.app] = byApp[w.app] || []).push(w)
            const seen = {}
            for (const p of Windows.pinned) {
                seen[p.id] = true
                out.push({ kind: "app", key: p.id, id: p.id, name: p.name, icon: p.icon, pinned: true, windows: byApp[p.id] || [] })
            }
            for (const w of Windows.list) {
                if (seen[w.app]) continue
                seen[w.app] = true
                out.push({ kind: "app", key: w.app, id: w.app, name: w.appName || w.app, icon: w.icon, pinned: false, windows: byApp[w.app] })
            }
        }
        out.push({ kind: "sep", key: "sep" })
        const byId = {}
        for (const w of Windows.list) byId[w.id] = w
        for (const id of minOrder) {
            const w = byId[id]
            if (w) out.push({ kind: "min", key: "min:" + id, id: id, name: w.title, icon: w.icon })
        }
        out.push({ kind: "trash", key: "trash", name: "Trash" })
        return out
    }

    // Minimised windows in the order they were minimised (new ones go last, next to the Trash).
    property var minOrder: []
    function updateMinOrder() {
        const mins = Windows.list.filter(w => w.minimized).map(w => w.id)
        const keep = minOrder.filter(id => mins.includes(id))
        for (const id of mins) if (!keep.includes(id)) keep.push(id)
        if (JSON.stringify(keep) !== JSON.stringify(minOrder)) minOrder = keep
    }
    Connections { target: Windows; function onListChanged() { root.updateMinOrder() } }
    Component.onCompleted: { updateMinOrder(); syncKeys(); ready = true }
    // The Repeater is keyed by these stable strings (via ScriptModel), so icons
    // survive updates instead of being rebuilt on every window change — keeping
    // the hover cursor, magnification and bounce intact.
    readonly property var keys: entries.map(e => e.key)
    readonly property var byKey: {
        const m = {}
        for (const e of entries) m[e.key] = e
        return m
    }

    // ---------- slide in / out ----------
    // Icons that leave (e.g. a minimised tile you just clicked) stay in the row a
    // moment and shrink to nothing, so their neighbours slide over instead of
    // jumping; new icons grow in from nothing the same way.
    property var displayKeys: []      // what the Repeater shows (current + leaving)
    property var leaving: ({})        // key -> true while animating out
    property var lastByKey: ({})      // last known entry for each key (leaving ones need it)
    property bool ready: false        // no grow-in animation for the first layout

    function syncKeys() {
        const cur = keys
        const inCur = {}
        for (const k of cur) inCur[k] = true
        const lv = Object.assign({}, leaving)
        for (const k of cur) delete lv[k]                 // came back before it finished leaving
        const out = [], pushed = {}
        let j = 0
        for (const k of displayKeys) {                    // keep old order; slot leavers where they were
            if (inCur[k]) {
                while (j < cur.length && !pushed[k]) { if (!pushed[cur[j]]) { out.push(cur[j]); pushed[cur[j]] = true } j++ }
            } else if (!pushed[k]) {
                lv[k] = true; out.push(k); pushed[k] = true
            }
        }
        for (; j < cur.length; j++) if (!pushed[cur[j]]) { out.push(cur[j]); pushed[cur[j]] = true }
        const lb = Object.assign({}, lastByKey, byKey)
        lastByKey = lb
        leaving = lv
        if (JSON.stringify(out) !== JSON.stringify(displayKeys)) displayKeys = out
    }
    function finishLeave(key) {
        if (!leaving[key]) return
        const lv = Object.assign({}, leaving); delete lv[key]; leaving = lv
        displayKeys = displayKeys.filter(k => k !== key)
    }
    onKeysChanged: syncKeys()

    // ---------- magnification ----------
    HoverHandler { id: hover }
    // Cursor offset from the row's centre. The row stays centred while it grows,
    // and zoom is computed from each item's *resting* position, so there's no feedback.
    readonly property real cursor: hover.hovered ? hover.point.position.x - width / 2 : 1e6
    readonly property var baseWidths: entries.map(e => e.kind === "sep" ? 13 : Theme.dockSlot)
    readonly property real baseTotal: baseWidths.reduce((a, b) => a + b, 0)
    function baseCenter(i) {
        let x = 0
        for (let k = 0; k < i; k++) x += baseWidths[k]
        return x + baseWidths[i] / 2 - baseTotal / 2
    }
    function zoomAt(i) {
        const range = Theme.dockSlot * 2.6
        const d = Math.abs(cursor - baseCenter(i))
        return d >= range ? 1 : 1 + (Theme.dockMagnify - 1) * (Math.cos(Math.PI * d / range) + 1) / 2
    }

    // ---------- tell the genie effect where each app's icon is ----------
    // While the dock is hidden, every window pours to the middle of the bottom
    // screen edge (where the dock comes from); while it's up, into its icon/tile.
    readonly property bool dockShown: root.parent?.shown ?? true
    onDockShownChanged: reporter.triggered()   // switch targets the moment it slides
    Timer {
        id: reporter
        interval: 400; running: true; repeat: true
        property string last: ""
        onTriggered: {
            const scr = root.win?.screen
            if (!scr || scr !== Quickshell.screens[0]) return
            if (hover.hovered && Theme.dockMagnify > 1) return   // skip while magnified
            // Measure against where the dock sits when shown (it auto-hides below the screen).
            const top = scr.y + scr.height - Theme.gap - Theme.dockHeight
            const rect = it => {
                const x = it.mapToItem(null, 0, 0).x
                const y = it.mapToItem(root.parent, 0, 0).y   // relative to the dock itself
                return [scr.x + x, top + y, it.width, it.height]
            }
            const map = {}
            if (!root.dockShown) {
                const edge = [scr.x + scr.width / 2 - 30, scr.y + scr.height - 2, 60, 2]
                for (const w of Windows.list) map[w.id] = edge
                const s = JSON.stringify(map)
                if (s !== last) { last = s; Windows.reportRects(map) }
                return
            }
            // A newly minimised window's tile takes the Trash's spot, and the dock
            // re-centres by half a slot - so that's where the genie should aim.
            let next = null
            for (let i = 0; i < items.count; i++) {
                const it = items.itemAt(i)
                if (it && it.entry.kind === "trash") { next = rect(it); next[0] -= Theme.dockSlot / 2 }
            }
            for (let i = 0; i < items.count; i++) {
                const it = items.itemAt(i)
                if (!it || it.isLeaving) continue
                if (it.entry.kind === "min") map[it.entry.id] = rect(it)          // restore: out of its tile
                else if (it.entry.kind === "app" && next)
                    for (const w of it.entry.windows) if (!w.minimized) map[w.id] = next   // minimise: into the new tile
            }
            const s = JSON.stringify(map)
            if (s !== last) { last = s; Windows.reportRects(map) }
        }
    }

    Repeater {
        id: items
        model: ScriptModel { values: root.displayKeys }

        Item {
            id: item
            required property string modelData   // the entry's key
            required property int index
            readonly property var entry: root.byKey[modelData] ?? root.lastByKey[modelData] ?? ({ kind: "sep" })
            readonly property bool isSep: entry.kind === "sep"
            readonly property bool isLeaving: root.leaving[modelData] === true

            // 0..1: grows in when added, shrinks out when removed (neighbours slide).
            property bool born: false
            Component.onCompleted: born = true
            property real presence: isLeaving ? 0 : (born || !root.ready ? 1 : 0)
            Behavior on presence { enabled: root.ready; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            onPresenceChanged: if (isLeaving && presence <= 0) root.finishLeave(modelData)
            opacity: presence
            readonly property bool running: (entry.windows?.length ?? 0) > 0
            property real zoom: isSep ? 1 : root.zoomAt(index)
            Behavior on zoom { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }

            Layout.preferredWidth: (isSep ? 13 : Theme.dockSlot * zoom) * presence
            Layout.preferredHeight: Theme.dockSlot
            Layout.alignment: Qt.AlignBottom

            // --- divider ---
            Rectangle {
                visible: item.isSep
                anchors.centerIn: parent
                width: 1; height: Theme.dockIcon * 0.8
                color: "#40ffffff"
            }

            // --- icon (rendered at full magnified size so it stays sharp) ---
            Item {
                id: iconBox
                visible: !item.isSep
                width: Theme.dockIcon * item.zoom
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: (Theme.dockSlot - Theme.dockIcon) / 2
                transform: Translate { id: bounce; y: 0 }
                opacity: area.pressed ? 0.55 : 1   // macOS-style press feedback
                scale: item.presence               // shrink/grow with the slot when leaving/arriving
                transformOrigin: Item.Bottom
                Behavior on opacity { NumberAnimation { duration: 80 } }

                // minimised window: framed app icon (KWin won't give us a window thumbnail)
                Rectangle {
                    visible: item.entry.kind === "min"
                    anchors.fill: parent
                    anchors.margins: parent.width * 0.04
                    radius: width * 0.18
                    color: "#26ffffff"
                    border.color: "#33ffffff"
                    Rectangle {   // little title bar
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 3 }
                        height: parent.height * 0.14; radius: height / 2
                        color: "#33ffffff"
                    }
                }
                IconImage {
                    visible: item.entry.kind === "app" || item.entry.kind === "trash" || item.entry.kind === "min"
                    anchors.fill: parent
                    anchors.margins: item.entry.kind === "min" ? parent.width * 0.22 : 0
                    anchors.topMargin: item.entry.kind === "min" ? parent.width * 0.3 : 0
                    implicitSize: Math.round(Theme.dockIcon * Theme.dockMagnify)
                    source: {
                        if (item.entry.kind === "trash")
                            return Quickshell.iconPath(Windows.trashFull ? "user-trash-full" : "user-trash")
                        const i = item.entry.icon ?? ""
                        return i.startsWith("/") ? "file://" + i : Quickshell.iconPath(i, "application-x-executable")
                    }
                }
                // Launchpad-style tile for the app launcher
                Rectangle {
                    visible: item.entry.kind === "launcher"
                    anchors.fill: parent
                    anchors.margins: parent.width * 0.06
                    radius: width * 0.24
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#5b5b66" }
                        GradientStop { position: 1; color: "#2b2b33" }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "󰀻"
                        color: "white"
                        font.family: Theme.font; font.pixelSize: parent.width * 0.55
                    }
                }
            }

            // --- running dot ---
            Rectangle {
                visible: item.running
                width: 5; height: 5; radius: 2.5
                color: "#e6ffffff"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -3
            }

            // --- name bubble above the hovered icon ---
            Rectangle {
                visible: area.containsMouse && !item.isSep && Menus.open !== "dock"
                anchors.horizontalCenter: parent.horizontalCenter
                y: iconBox.y - height - 12
                width: label.implicitWidth + 20; height: 26; radius: 8
                color: Theme.bgSolid; border.color: Theme.border
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: item.entry.name ?? ""
                    color: Theme.fg; font.family: Theme.font; font.pixelSize: 12
                }
            }

            // --- launch bounce (until a window appears, or 6 s) ---
            property bool launching: false
            onRunningChanged: if (running) launching = false
            Timer { interval: 6000; running: item.launching; onTriggered: item.launching = false }
            SequentialAnimation {
                running: item.launching
                loops: Animation.Infinite
                onStopped: bounce.y = 0
                NumberAnimation { target: bounce; property: "y"; to: -Theme.dockIcon * 0.4; duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { target: bounce; property: "y"; to: 0; duration: 260; easing.type: Easing.InQuad }
            }

            MouseArea {
                id: area
                enabled: !item.isSep && !item.isLeaving
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const e = item.entry
                    if (mouse.button === Qt.RightButton) {
                        const p = item.mapToItem(null, item.width / 2, 0)
                        const scr = root.win.screen
                        const dockTop = scr.height - Theme.gap - Theme.dockHeight   // shown position
                        Menus.openDock(e, p.x, dockTop)
                        return
                    }
                    if (e.kind === "min") {
                        Windows.focus(e.id)   // restores it (genie out of this tile)
                    } else if (e.kind === "launcher") {
                        Quickshell.execDetached(["qdbus6", "org.kde.krunner", "/App", "display"])
                    } else if (e.kind === "trash") {
                        Windows.trash("open")
                    } else if (mouse.button === Qt.MiddleButton || !item.running) {
                        Windows.launch(e.id)
                        if (!item.running) item.launching = true
                    } else {
                        // KWin decides with its live state (see toggle_app in windows.py),
                        // so rapid clicks each toggle exactly once.
                        Windows.toggleApp(e.id)
                    }
                }
                // Scroll over a running app to cycle through its windows.
                onWheel: wheel => {
                    const ws = (item.entry.windows ?? []).filter(w => !w.minimized)
                    if (ws.length === 0) return
                    const a = ws.findIndex(w => w.active)
                    const step = wheel.angleDelta.y < 0 ? 1 : -1
                    Windows.focus(ws[((a < 0 ? 0 : a + step) + ws.length) % ws.length].id)
                }
            }
        }
    }
}
