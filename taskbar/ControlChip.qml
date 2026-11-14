import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// Wi-Fi, Bluetooth and sound behind one top-bar icon (like macOS's Control Center icon).
// Click opens the Control Center; scrolling over it changes the volume.
Item {
    id: root

    // Wi-Fi
    readonly property var dev: Networking.devices.values.find(d => d.scannerEnabled !== undefined) ?? null
    readonly property var current: dev ? dev.networks.values.find(n => n.connected) ?? null : null
    function bars(n) {
        if (!Networking.wifiEnabled) return "󰤮"
        if (!n) return "󰤯"
        const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength
        return ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(s * 4))]
    }
    // Bluetooth
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    // Sound
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    PwObjectTracker { objects: [root.sink] }

    readonly property bool available: dev !== null || adapter !== null || sink !== null

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // One icon, like macOS's Control Center: two stacked toggle switches.
    Item {
        id: row
        implicitWidth: 18; implicitHeight: 16
        Rectangle {   // upper toggle, knob right
            x: 0; y: 0.5; width: 18; height: 7.5; radius: height / 2
            color: "transparent"; border.width: 1.4; border.color: Theme.fg
            Rectangle { x: parent.width - width - 1.4; anchors.verticalCenter: parent.verticalCenter
                        width: 4.2; height: 4.2; radius: 2.1; color: Theme.fg }
        }
        Rectangle {   // lower toggle, knob left
            x: 0; y: 8.5; width: 18; height: 7.5; radius: height / 2
            color: "transparent"; border.width: 1.4; border.color: Theme.fg
            Rectangle { x: 1.4; anchors.verticalCenter: parent.verticalCenter
                        width: 4.2; height: 4.2; radius: 2.1; color: Theme.fg }
        }
    }

    MouseArea {
        anchors.fill: parent; anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Menus.toggle("control", root)
        onWheel: wheel => {
            if (!root.sink) return
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            root.sink.audio.volume = Math.max(0, Math.min(1, root.vol + step))
        }
    }
}
