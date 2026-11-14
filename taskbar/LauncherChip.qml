import QtQuick
import Quickshell

// App launcher button. Click: KRunner (type to search apps). Right click: Overview.
Text {
    readonly property bool available: true
    text: "󰣇"
    color: area.containsMouse ? Theme.accent : Theme.fg
    font.family: Theme.font; font.pixelSize: 26
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: area
        anchors.fill: parent; anchors.margins: -6
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton
            ? Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Overview"])
            : Quickshell.execDetached(["qdbus6", "org.kde.krunner", "/App", "display"])
    }
}
