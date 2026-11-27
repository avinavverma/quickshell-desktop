import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Desktop widget: a Firefox search bar in the taskbar's glass style. Type and press Enter:
// something that looks like an address (example.com, http://…, localhost:3000) opens directly,
// anything else is searched with Firefox's default search engine. Esc clears it.
// Sits on the desktop (below windows); drag it by its edge, it snaps to the screen's centre
// lines and double-click centres it. Position saved in search-widget.json.
// Switch: "Search bar" (group "Desktop") in Switchboard.
PanelWindow {
    id: win

    readonly property real barW: 600
    readonly property real barH: 58
    readonly property real scrW: screen?.width ?? 1920
    readonly property real scrH: screen?.height ?? 1080
    property real px: (scrW - barW) / 2
    property real py: Math.round(scrH * 0.22)
    property bool snapX: false
    property bool snapY: false

    anchors { top: true; left: true }
    margins { left: px; top: py }
    implicitWidth: barW
    readonly property real rowH: 46
    readonly property int shownRows: input.activeFocus ? Math.min(suggestions.length, 5) : 0
    readonly property real listH: shownRows > 0 ? shownRows * rowH + 12 : 0
    implicitHeight: barH + (listH > 0 ? listH + 8 : 0)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "taskbar-search-widget"
    // Bottom layer normally (below windows). KWin only gives the keyboard to Top / Overlay layer
    // surfaces, so while you're looking at the desktop (nothing in front) the bar is on Top.
    WlrLayershell.layer: Windows.desktopVisible ? WlrLayer.Top : WlrLayer.Bottom
    // While you're looking at the desktop (no window in front) the bar holds the keyboard, so
    // typing anywhere on the desktop types into it; with a window in front it only takes the
    // keyboard when clicked.
    readonly property bool onDesktop: Windows.desktopVisible
    WlrLayershell.keyboardFocus: onDesktop ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    onOnDesktopChanged: if (onDesktop) input.forceActiveFocus(); else if (!input.text) input.focus = false
    Component.onCompleted: if (onDesktop) input.forceActiveFocus()
    color: "transparent"
    // Same recipe as the media card: Theme.bg glass + 1 px Theme.border, antialiased rounded rectangle.
    BackgroundEffect.blurRegion: Region {
        item: bar; radius: win.barH / 2
        Region { item: list; radius: 18 }
    }

    FileView {
        id: posFile
        path: Qt.resolvedUrl("search-widget.json")
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                if (typeof o.x === "number") win.px = o.x
                if (typeof o.y === "number") win.py = o.y
            } catch (e) {}
        }
    }
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: posFile.setText(JSON.stringify({ x: Math.round(win.px), y: Math.round(win.py) }))
    }

    // ---------- autofill from Firefox's history ----------
    // firefox-history.py reads the most-used sites (for the inline completion of an address) and
    // pages (for the list below the bar) from Firefox's own database. Refreshed when you click in.
    property var origins: []          // [[host, prefix], ...] most used first
    property var places: []           // [[url, title], ...]
    property double loadedAt: 0
    Process {
        id: history
        command: ["python3", Qt.resolvedUrl("firefox-history.py").toString().replace("file://", "")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text); win.origins = d.origins; win.places = d.places; win.loadedAt = Date.now() } catch (e) {}
            }
        }
    }
    function refreshHistory() { if (!history.running && Date.now() - loadedAt > 120000) history.running = true }

    property bool suppressAutofill: false     // after Backspace, like Firefox, don't complete again
    property int prevLen: 0
    property int selected: -1                 // highlighted suggestion (arrow keys), -1 = none
    readonly property string query: input.text.trim()
    // Inline completion: the rest of the most-used site whose name starts with what you typed.
    readonly property string ghost: {
        const q = input.text.toLowerCase()
        if (!q || /\s/.test(q) || suppressAutofill || input.cursorPosition !== input.text.length) return ""
        for (const o of origins) {
            const h = o[0].toLowerCase(), bare = h.startsWith("www.") ? h.slice(4) : h
            if (bare.startsWith(q) && bare.length > q.length) return bare.slice(q.length)
            if (h.startsWith(q) && h.length > q.length) return h.slice(q.length)
        }
        return ""
    }
    // The list: pages whose address or title contains every word typed, most used first.
    readonly property var suggestions: {
        const q = query.toLowerCase()
        if (!q) return []
        const words = q.split(/\s+/)
        const out = []
        for (const p of places) {
            const hay = (p[0] + " " + p[1]).toLowerCase()
            if (words.every(w => hay.indexOf(w) >= 0)) out.push({ url: p[0], title: p[1] })
            if (out.length >= 5) break
        }
        return out
    }
    function prettyUrl(u) { return u.replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "") }

    // ---------- what Enter does ----------
    function looksLikeUrl(t) {
        if (/\s/.test(t)) return false
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(t) || /^(about|file):/i.test(t)) return true
        if (/^localhost(:\d+)?(\/.*)?$/i.test(t)) return true
        if (/^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$/.test(t)) return true
        return /^[^\/.]+(\.[^\/.]+)*\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(t)      // example.com, a.b.co.uk/x
    }
    function go(text) {
        const t = text.trim()
        if (!t) return
        let args
        if (looksLikeUrl(t)) {
            const url = /^[a-z][a-z0-9+.-]*:/i.test(t) ? t : (/^(localhost|\d)/i.test(t) ? "http://" : "https://") + t
            args = ["firefox", "--new-tab", url]
        } else {
            args = ["firefox", "--search", t]
        }
        // own scope, like the dock's launcher, so Firefox doesn't live inside the taskbar's service
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--slice=app.slice"].concat(args))
        input.text = ""
        input.focus = false
        raiseFirefox.restart()
    }
    // A running Firefox opens the tab but may not come to the front by itself on Wayland.
    Timer {
        id: raiseFirefox
        interval: 450
        onTriggered: {
            const w = Windows.list.find(w => /firefox/i.test(w.app))
            if (w) Windows.focus(w.id)
        }
    }

    Rectangle {
        id: bar
        width: win.barW; height: win.barH
        radius: height / 2
        antialiasing: true
        color: Theme.bg
        border.width: 1
        // a fainter hairline than the media card's; it doesn't change when you click into the bar
        // (only the centre-snap while dragging lights it up)
        border.color: win.snapX || win.snapY ? Theme.accent : "#24ffffff"
        Behavior on border.color { ColorAnimation { duration: 150 } }
        GlassSheen {}

        // Drag by the bar (outside the text); snaps to the centre lines; double-click centres.
        MouseArea {
            id: dragArea
            anchors.fill: parent
            property point start
            readonly property real near: 14
            function snap(v, targets) {
                for (const t of targets) if (Math.abs(v - t) < near) return t
                return v
            }
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
            onPressed: m => { start = mapToItem(null, m.x, m.y) }
            onPositionChanged: m => {
                if (!pressed) return
                const p = mapToItem(null, m.x, m.y)
                const cx = (win.scrW - win.barW) / 2, cy = (win.scrH - win.barH) / 2
                const nx = snap(p.x + win.px - start.x, [cx, 24, win.scrW - win.barW - 24])
                const ny = snap(p.y + win.py - start.y, [cy, 52, win.scrH - win.barH - 24])
                win.snapX = nx === cx; win.snapY = ny === cy
                win.px = Math.max(0, nx); win.py = Math.max(0, ny)
            }
            onReleased: { win.snapX = false; win.snapY = false; saveTimer.restart() }
            onDoubleClicked: { win.px = (win.scrW - win.barW) / 2; win.py = (win.scrH - win.barH) / 2; saveTimer.restart() }
        }

        Text {     // a plain magnifier in the bar's own colours (the coloured Firefox logo clashed)
            id: logo
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            text: "󰍉"
            color: Qt.rgba(1, 1, 1, 0.62)
            font.family: Theme.iconFont; font.pixelSize: 20
        }

        TextInput {
            id: input
            anchors { left: logo.right; leftMargin: 14; right: hint.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: "white"
            font.family: Theme.font; font.pixelSize: 17
            clip: true
            cursorVisible: true
            cursorDelegate: Rectangle {
                width: 2; radius: 1
                color: Theme.fg
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: true
                    NumberAnimation { to: 0; duration: 480; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 480; easing.type: Easing.InOutSine }
                }
            }
            onAccepted: {
                if (win.selected >= 0 && win.selected < win.shownRows) win.go(win.suggestions[win.selected].url)
                else win.go(text + win.ghost)
            }
            onTextChanged: {
                win.suppressAutofill = text.length < win.prevLen
                win.prevLen = text.length
                win.selected = -1
            }
            onActiveFocusChanged: if (activeFocus) win.refreshHistory()
            Keys.onTabPressed: if (win.ghost) { text = text + win.ghost; cursorPosition = text.length }
            Keys.onRightPressed: event => {
                if (win.ghost && cursorPosition === text.length) { text = text + win.ghost; cursorPosition = text.length }
                else event.accepted = false
            }
            Keys.onDownPressed: if (win.shownRows > 0) win.selected = Math.min(win.shownRows - 1, win.selected + 1)
            Keys.onUpPressed: win.selected = Math.max(-1, win.selected - 1)
            Keys.onEscapePressed: { if (text) text = ""; else focus = false }
            // the rest of the completed address, greyed out after the cursor
            Text {
                x: input.contentWidth
                anchors.verticalCenter: parent.verticalCenter
                visible: win.ghost !== "" && win.selected < 0
                text: win.ghost
                color: Qt.rgba(1, 1, 1, 0.38)
                font: input.font
            }
            // the text field takes clicks; the rest of the bar is for dragging
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: m => { input.forceActiveFocus(); m.accepted = false }
            }
        }

        // What Enter will do, on the right.
        Rectangle {
            id: hint
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            visible: input.text.trim() !== ""
            width: hintText.implicitWidth + 18; height: 28; radius: 14
            color: "#26ffffff"
            Text {
                id: hintText
                anchors.centerIn: parent
                text: (win.selected >= 0 || win.ghost || win.looksLikeUrl(input.text.trim()) ? "Go" : "Search") + "  ↵"
                color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
    }

    // ---------- suggestions from history, below the bar ----------
    Rectangle {
        id: list
        y: win.barH + 8
        width: win.barW
        height: win.listH
        visible: win.shownRows > 0
        radius: 18
        antialiasing: true
        color: Theme.bg
        border.width: 1; border.color: "#24ffffff"
        GlassSheen {}
        Column {
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: win.suggestions.slice(0, win.shownRows)
                Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width; height: win.rowH
                    radius: 12
                    color: win.selected === index ? "#33ffffff" : rowArea.containsMouse ? "#1fffffff" : "transparent"
                    Text {
                        id: rowIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "󰋚"         // history
                        color: Theme.fgDim; font.family: Theme.iconFont; font.pixelSize: 16
                    }
                    Column {
                        anchors { left: rowIcon.right; leftMargin: 12; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text {
                            width: parent.width
                            text: modelData.title || win.prettyUrl(modelData.url)
                            color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: win.prettyUrl(modelData.url)
                            color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.go(modelData.url)
                    }
                }
            }
        }
    }
}
