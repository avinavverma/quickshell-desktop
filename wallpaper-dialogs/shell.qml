// wallpaper-dialogs: the "Serious error occurred" boxes in the wallpaper lift and
// tilt toward the cursor when hovered.
//
// A full-screen, transparent layer-shell window on the Bottom layer (above Plasma's desktop,
// below every normal window and the taskbar) draws each dialog as its own item over
// Plasma's own copy of the wallpaper, so desktop icons and rubber-band selection keep working. Only the dialog rectangles take input; the
// rest of the screen passes clicks through to the Plasma desktop.
//
// Outlines live in dialogs.json (image pixels) and reload on save.
// Draw/adjust them with tools/edit.sh (or `qs -p <dir> ipc call editor toggle`).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: shell

    property var cfg: null        // normalized: dialogs = [{name, poly}]
    property bool editing: false

    function normalize(c) {
        c.dialogs = c.dialogs.map((d, i) => ({
            name: d.name || ("dialog-" + (i + 1)),
            poly: d.poly || [[d.x, d.y], [d.x + d.w, d.y], [d.x + d.w, d.y + d.h], [d.x, d.y + d.h]]
        }))
        return c
    }

    FileView {
        id: cfgFile
        path: Qt.resolvedUrl("dialogs.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { shell.cfg = shell.normalize(JSON.parse(text())) }
            catch (e) { console.warn("dialogs.json:", e) }
        }
    }

    // Switchboard shows the "Outline editor" switch from modules.json. Flipping it opens or
    // closes the editor; closing it any other way (S, Esc, edit.sh) flips the switch back.
    property var modules: []
    property bool eyeOn: true
    property bool painting: false
    property int maskRev: 0
    readonly property url maskUrl: Qt.resolvedUrl("eye-mask.png")
    FileView {
        id: modFile
        path: Qt.resolvedUrl("modules.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                shell.modules = JSON.parse(text())
                const m = shell.modules.find(x => x.id === "editor")
                if (m && m.enabled !== shell.editing) shell.editing = m.enabled
                const t = shell.modules.find(x => x.id === "eyetint")
                shell.eyeOn = t ? t.enabled : true
                const pm = shell.modules.find(x => x.id === "eyepaint")
                if (pm && pm.enabled !== shell.painting) shell.painting = pm.enabled
            } catch (e) { console.warn("modules.json:", e) }
        }
    }
    function syncModule(id, on) {
        const m = modules.find(x => x.id === id)
        if (m && m.enabled !== on) {
            m.enabled = on
            modFile.setText(JSON.stringify(modules, null, 1))
        }
    }
    onEditingChanged: syncModule("editor", editing)
    onPaintingChanged: syncModule("eyepaint", painting)

    IpcHandler {
        target: "editor"
        function toggle(): void { shell.editing = !shell.editing }
        function start(): void { shell.editing = true }
        function stop(): void { shell.editing = false }
    }

    IpcHandler {
        target: "eyepaint"
        function toggle(): void { shell.painting = !shell.painting }
        function start(): void { shell.painting = true }
        function stop(): void { shell.painting = false }
    }

    LazyLoader {
        active: shell.painting && shell.cfg !== null
        EyePainter {
            screen: Quickshell.screens[0]
            src: Qt.resolvedUrl(shell.cfg.image)
            patch: Qt.rect(shell.eyeCfg.rect[0], shell.eyeCfg.rect[1], shell.eyeCfg.rect[2], shell.eyeCfg.rect[3])
            maskUrl: shell.maskUrl
            savePath: shell.maskUrl.toString().replace("file://", "")
            onSaved: { shell.maskRev++; shell.painting = false }
            onCancelled: shell.painting = false
        }
    }

    LazyLoader {
        active: shell.editing && shell.cfg !== null
        Editor {
            screen: Quickshell.screens[0]
            src: Qt.resolvedUrl(shell.cfg.image)
            iw: shell.cfg.imageWidth
            ih: shell.cfg.imageHeight
            polys: shell.cfg.dialogs.map(d => d.poly.map(p => [p[0], p[1]]))
            names: shell.cfg.dialogs.map(d => d.name)
            onSaved: (polys, names) => {
                const out = {
                    image: shell.cfg.image, imageWidth: shell.cfg.imageWidth, imageHeight: shell.cfg.imageHeight, float: shell.cfg.float, eye: shell.cfg.eye,
                    dialogs: polys.map((p, i) => ({ name: names[i], poly: p }))
                }
                cfgFile.setText(JSON.stringify(out, null, 1))
                shell.editing = false
            }
            onCancelled: shell.editing = false
        }
    }

    // ---------- eye follows the cover art ----------
    // The taskbar writes the playing song's accent colour to $XDG_RUNTIME_DIR/taskbar-accent
    // ("#rrggbb", or "none"). The eye patch of the wallpaper is re-hued to it, and fades back
    // to the original pink when nothing plays. dialogs.json may set
    // "eye": {"rect": [x, y, w, h] (image pixels), "spread": 0.45}.
    readonly property var eyeCfg: Object.assign({ rect: [1448, 768, 944, 604], spread: 0.45, variety: 0.0 }, cfg ? cfg.eye : null)
    property color accent: "#e5484d"
    property bool accentOn: false
    property real eyeAmount: eyeOn && accentOn ? 1 : 0
    Behavior on accent { ColorAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    Behavior on eyeAmount { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp") + "/taskbar-accent"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim()
            if (/^#[0-9a-fA-F]{6}$/.test(t)) { shell.accent = t; shell.accentOn = true }
            else shell.accentOn = false
        }
        onLoadFailed: shell.accentOn = false
    }

    // ---------- idle float ----------
    // The boxes drift gently all the time. One shared clock drives every box.
    // dialogs.json may set "float": {"enabled": true, "amount": 1.0} (0.5 = calmer, 2 = floatier).
    readonly property var floatCfg: Object.assign({ enabled: true, amount: 1.0 }, cfg ? cfg.float : null)
    property real clock: 0
    // 30 updates a second is plenty for motion this slow, and half the cost of every frame.
    Timer {
        interval: 33
        running: shell.floatCfg.enabled
        repeat: true
        property real t0: Date.now()
        onTriggered: shell.clock = (Date.now() - t0) / 1000
    }

    Component { id: regionComp; Region {} }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "wallpaper-dialogs"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"   // Plasma's own wallpaper (and its desktop icons) shows through; we only draw the boxes

            readonly property url src: shell.cfg ? Qt.resolvedUrl(shell.cfg.image) : ""
            readonly property real iw: shell.cfg ? shell.cfg.imageWidth : 1
            readonly property real ih: shell.cfg ? shell.cfg.imageHeight : 1
            // Same as Plasma's "Scaled and Cropped": cover the screen, centred.
            readonly property real k: Math.max(width / iw, height / ih)
            readonly property real ox: (width - iw * k) / 2
            readonly property real oy: (height - ih * k) / 2

            // Input only over the dialogs.
            mask: Region { id: inputMask }
            function rebuildMask() {
                const rs = []
                for (let i = 0; i < dialogs.count; i++) {
                    const it = dialogs.itemAt(i)
                    if (it) rs.push(regionComp.createObject(inputMask, { item: it }))
                }
                for (const old of inputMask.regions) old.destroy()
                inputMask.regions = rs
            }
            Connections { target: shell; function onCfgChanged() { Qt.callLater(win.rebuildMask) } }

            // Same patch of the flat wallpaper, re-hued (so the eye is right even when no box is drawn).
            EyeTint {
                x: win.ox + shell.eyeCfg.rect[0] * win.k
                y: win.oy + shell.eyeCfg.rect[1] * win.k
                width: shell.eyeCfg.rect[2] * win.k
                height: shell.eyeCfg.rect[3] * win.k
                source: win.src
                clip: Qt.rect(shell.eyeCfg.rect[0], shell.eyeCfg.rect[1], shell.eyeCfg.rect[2], shell.eyeCfg.rect[3])
                accent: shell.accent
                amount: shell.eyeAmount
                spread: shell.eyeCfg.spread
                variety: shell.eyeCfg.variety
                mask: shell.maskUrl
                maskRev: shell.maskRev
            }

            Item {
                anchors.fill: parent
                Repeater {
                    id: dialogs
                    model: shell.cfg ? shell.cfg.dialogs : []
                    onCountChanged: Qt.callLater(win.rebuildMask)
                    Dialog {
                        required property var modelData
                        required property int index
                        entry: modelData
                        holes: shell.cfg.dialogs.slice(index + 1).map(d => d.poly)
                        order: index
                        clock: shell.clock
                        tintRect: shell.eyeCfg.rect
                        tintSpread: shell.eyeCfg.spread
                        tintVariety: shell.eyeCfg.variety
                        tintAccent: shell.accent
                        tintAmount: shell.eyeAmount
                        tintMask: shell.maskUrl
                        tintMaskRev: shell.maskRev
                        floating: shell.floatCfg.enabled
                        floatAmount: shell.floatCfg.amount
                        source: win.src
                        k: win.k
                        ox: win.ox
                        oy: win.oy
                    }
                }
            }
        }
    }
}
