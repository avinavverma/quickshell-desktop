import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

// Bluetooth: icon (+ connected device name). Click opens the Control Center.
Item {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connected: adapter ? adapter.devices.values.filter(d => d.connected) : []
    readonly property bool available: adapter !== null

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row
        spacing: 6
        Text {
            text: !root.adapter?.enabled ? "󰂲" : root.connected.length > 0 ? "󰂱" : "󰂯"
            color: root.adapter?.enabled ? Theme.fg : Theme.fgDim
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
