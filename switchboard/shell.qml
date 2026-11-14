import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Switchboard: a window listing everything in ~/Projects with on/off and start-at-login switches.
FloatingWindow {
    id: win
    title: "Switchboard"
    implicitWidth: 460
    implicitHeight: 560
    color: bg

    // ---- look ----
    readonly property color bg: "#101014"
    readonly property color card: "#1a1a20"
    readonly property color cardHover: "#22222a"
    readonly property color fg: "#f2f2f5"
    readonly property color fgDim: "#8a8a96"
    readonly property color accent: "#e5484d"
    readonly property color ok: "#4ade80"
    readonly property string font: "FantasqueSansM Nerd Font Propo"

    // ---- data ----
    readonly property string ctl: Qt.resolvedUrl("ctl.sh").toString().replace("file://", "")
    property var items: []
    property var pending: ({})   // "name:field" -> wanted value, while a change is in flight

    onVisibleChanged: if (!visible) Qt.quit()

    Process {
        id: lister
        command: [win.ctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { win.items = JSON.parse(text) } catch (e) { console.warn("bad list output:", text); return }
                // Drop pending flags once the real state matches what was asked for.
                const p = Object.assign({}, win.pending)
                for (const it of win.items) {
                    for (const f of ["running", "autostart"])
                        if (p[`${it.name}:${f}`] === it[f]) delete p[`${it.name}:${f}`]
                    for (const m of it.modules ?? [])
                        if (p[`${it.name}:mod:${m.id}`] === m.enabled) delete p[`${it.name}:mod:${m.id}`]
                }
                win.pending = p
            }
        }
    }

    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!lister.running) lister.running = true
    }

    function shown(item, field) {
        const p = pending[`${item.name}:${field}`]
        return p === undefined ? item[field] : p
    }
    function busy(item, field) { return pending[`${item.name}:${field}`] !== undefined }

    function toggle(item, field) {
        const want = !item[field]
        const p = Object.assign({}, pending); p[`${item.name}:${field}`] = want; pending = p
        const verb = field === "running" ? (want ? "start" : "stop") : (want ? "enable" : "disable")
        Quickshell.execDetached([ctl, verb, item.name])
        pendingTimeout.restart()
        refreshSoon.restart()
    }

    function toggleModule(item, mod) {
        const key = `${item.name}:mod:${mod.id}`
        const want = !mod.enabled
        const p = Object.assign({}, pending); p[key] = want; pending = p
        Quickshell.execDetached([ctl, "module", item.name, mod.id, String(want)])
        pendingTimeout.restart()
        refreshSoon.restart()
    }

    Timer { id: refreshSoon; interval: 300; onTriggered: if (!lister.running) lister.running = true }
    // If something never reaches the requested state, stop showing it as pending.
    Timer { id: pendingTimeout; interval: 8000; onTriggered: win.pending = ({}) }

    // Scrolls when the list is taller than the window.
    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
        spacing: 10

        RowLayout {
            Layout.bottomMargin: 6
            Text {
                text: "Switchboard"
                color: win.fg; font.family: win.font; font.pixelSize: 20; font.bold: true
                Layout.fillWidth: true
            }
            Text {
                readonly property int on: win.items.filter(i => i.running).length
                text: `${on} / ${win.items.length} running`
                color: win.fgDim; font.family: win.font; font.pixelSize: 13
            }
        }

        Text {
            visible: win.items.length === 0
            text: "Nothing in ~/Projects yet."
            color: win.fgDim; font.family: win.font; font.pixelSize: 14
        }

        Repeater {
            model: win.items

            Rectangle {
                id: row
                required property var modelData
                readonly property bool toggleable: modelData.kind !== "none"
                readonly property bool runBusy: win.busy(modelData, "running")

                Layout.fillWidth: true
                implicitHeight: header.height + (modList.visible ? modList.implicitHeight + 10 : 0)
                radius: 16
                color: rowHover.hovered ? win.cardHover : win.card
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: rowHover }

                RowLayout {
                    id: header
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16 }
                    height: 64
                    spacing: 12

                    // status dot
                    Rectangle {
                        implicitWidth: 10; implicitHeight: 10; radius: 5
                        color: row.modelData.running ? win.ok : "#44444e"
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: row.modelData.name
                            color: win.fg; font.family: win.font; font.pixelSize: 15; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: row.runBusy ? (win.shown(row.modelData, "running") ? "starting…" : "stopping…")
                                 : !row.toggleable ? "no run.sh or shell.qml"
                                 : row.modelData.kind === "quickshell" ? "Quickshell" : "run.sh"
                            color: win.fgDim; font.family: win.font; font.pixelSize: 12
                        }
                    }

                    // start-at-login
                    ColumnLayout {
                        visible: row.toggleable
                        spacing: 3
                        Toggle {
                            small: true
                            Layout.alignment: Qt.AlignHCenter
                            on: win.shown(row.modelData, "autostart")
                            busy: win.busy(row.modelData, "autostart")
                            onToggled: win.toggle(row.modelData, "autostart")
                        }
                        Text {
                            text: "at login"
                            Layout.alignment: Qt.AlignHCenter
                            color: win.fgDim; font.family: win.font; font.pixelSize: 10
                        }
                    }

                    // running on/off
                    Toggle {
                        on: win.shown(row.modelData, "running")
                        busy: row.runBusy
                        active: row.toggleable
                        onToggled: win.toggle(row.modelData, "running")
                    }
                }

                // modules inside this project (from its modules.json)
                ColumnLayout {
                    id: modList
                    visible: (row.modelData.modules ?? []).length > 0
                    anchors { left: parent.left; right: parent.right; top: header.bottom; leftMargin: 38; rightMargin: 16 }
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true; Layout.bottomMargin: 4
                        implicitHeight: 1; color: "#2a2a33"
                    }

                    Repeater {
                        model: row.modelData.modules ?? []

                        ColumnLayout {
                            id: modRow
                            required property var modelData
                            required property int index
                            readonly property string key: `${row.modelData.name}:mod:${modelData.id}`
                            readonly property bool on: win.pending[key] ?? modelData.enabled
                            // Optional "group" field: show a heading where the group changes.
                            readonly property string group: modelData.group ?? ""
                            readonly property bool newGroup: group !== ""
                                && (index === 0 || (row.modelData.modules[index - 1].group ?? "") !== group)
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                visible: modRow.newGroup
                                text: modRow.group.toUpperCase()
                                color: win.accent
                                font.family: win.font; font.pixelSize: 10; font.bold: true
                                font.letterSpacing: 1.2
                                Layout.topMargin: modRow.index === 0 ? 2 : 10
                                Layout.bottomMargin: 2
                            }

                        RowLayout {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            spacing: 10

                            Text {
                                text: modRow.modelData.name
                                color: modRow.on ? win.fg : win.fgDim
                                font.family: win.font; font.pixelSize: 13
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Toggle {
                                small: true
                                on: modRow.on
                                busy: win.pending[modRow.key] !== undefined
                                onToggled: win.toggleModule(row.modelData, modRow.modelData)
                            }
                        }
                        }
                    }
                }
            }
        }
    }

    }

    component Toggle: Rectangle {
        id: t
        property bool on
        property bool busy
        property bool active: true
        property bool small: false
        signal toggled()

        implicitWidth: small ? 34 : 46
        implicitHeight: small ? 20 : 26
        radius: height / 2
        opacity: active ? (busy ? 0.6 : 1) : 0.3
        color: on ? win.accent : "#3a3a44"
        Behavior on color { ColorAnimation { duration: 180 } }

        Rectangle {
            readonly property int pad: t.small ? 2 : 3
            width: t.height - pad * 2; height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: t.on ? t.width - width - pad : pad
            color: "white"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            enabled: t.active && !t.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: t.toggled()
        }
    }
}
