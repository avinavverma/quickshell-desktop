import QtQuick

// Round icon button: filled with the accent colour when on.
Rectangle {
    id: b
    property string icon
    property bool on: false
    property int size: 30
    signal clicked()

    implicitWidth: size; implicitHeight: size
    radius: size / 2
    color: on ? Theme.accent : area.containsMouse ? "#40ffffff" : "#2affffff"
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
        anchors.centerIn: parent
        text: b.icon
        color: "white"
        font.family: Theme.font; font.pixelSize: Math.round(b.size * 0.5)
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
