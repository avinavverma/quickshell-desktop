import QtQuick
import QtQuick.Layouts

// Window buttons for the active window (macOS colours, right end of the top bar).
// Red closes, yellow minimises (through KWin, so the genie always plays),
// green toggles maximise. With maximised windows borderless, these act as
// their title bar.
RowLayout {
    id: root
    readonly property var win: Windows.list.find(w => w.active && !w.minimized) ?? null
    // Only when the active window has no title bar of its own (a maximised,
    // borderless KDE window) - otherwise it already shows its own buttons.
    readonly property bool available: win !== null && win.titlebarless === true
    spacing: 8

    Light { color: "#febc2e"; onClicked: Windows.minimize(root.win.id) }
    Light { color: "#28c840"; onClicked: Windows.maximize(root.win.id) }
    Light { color: "#ff5f57"; onClicked: Windows.close(root.win.id) }

    component Light: Rectangle {
        id: light
        signal clicked()
        implicitWidth: 13; implicitHeight: 13
        radius: width / 2
        border.color: Qt.darker(color, 1.25)
        border.width: 0.5
        opacity: lightArea.pressed ? 0.7 : 1

        MouseArea {
            id: lightArea
            anchors.fill: parent; anchors.margins: -3
            cursorShape: Qt.PointingHandCursor
            onClicked: light.clicked()
        }
    }
}
