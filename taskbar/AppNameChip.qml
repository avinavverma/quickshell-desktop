import QtQuick
import Quickshell
import Quickshell.Widgets

// The active app's icon (no name), at the left of the top bar where macOS shows the app menu.
Item {
    id: root
    readonly property var win: Windows.list.find(w => w.active && !w.minimized) ?? null
    readonly property bool available: win !== null
    implicitWidth: 20; implicitHeight: 20

    IconImage {
        anchors.fill: parent
        implicitSize: 20
        source: {
            const i = root.win?.icon ?? ""
            return i.startsWith("/") ? "file://" + i : Quickshell.iconPath(i, "application-x-executable")
        }
    }
}
