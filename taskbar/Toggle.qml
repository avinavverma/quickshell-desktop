import QtQuick

// Small on/off switch.
Rectangle {
    id: t
    property bool on
    signal toggled()

    implicitWidth: 40; implicitHeight: 22
    radius: height / 2
    color: on ? Theme.accent : "#3a3a44"
    Behavior on color { ColorAnimation { duration: 160 } }

    Rectangle {
        width: t.height - 6; height: width; radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: t.on ? t.width - width - 3 : 3
        color: "white"
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled()
    }
}
