import QtQuick
import QtQuick.Layouts
import Quickshell.Networking

// Wi-Fi: signal icon + network name. Click opens the Control Center.
Item {
    id: root
    readonly property var dev: Networking.devices.values.find(d => d.scannerEnabled !== undefined) ?? null
    readonly property var current: dev ? dev.networks.values.find(n => n.connected) ?? null : null
    readonly property bool available: dev !== null

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    function bars(n) {
        if (!Networking.wifiEnabled) return "󰤮"
        if (!n) return "󰤯"
        const s = n.signalStrength > 1 ? n.signalStrength / 100 : n.signalStrength
        return ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(s * 4))]
    }

    RowLayout {
        id: row
        spacing: 6
        Text {
            text: root.bars(root.current)
            color: Theme.fg
            font.family: Theme.iconFont; font.pixelSize: 16
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent; anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Menus.toggle("control", root)
    }
}
