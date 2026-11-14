import QtQuick

// macOS-style slider: a pill that fills with white, icon inside on the left.
Item {
    id: s
    property real value: 0          // 0..1
    property string icon
    signal moved(real value)

    implicitHeight: 24

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: "#2affffff"
        clip: true

        Rectangle {
            width: Math.max(track.height, track.width * s.value)
            height: parent.height
            radius: height / 2
            color: "#f2f2f5"
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 120 } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            text: s.icon
            color: "#2a2a30"   // sits on the white fill
            font.family: Theme.font; font.pixelSize: 13
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function set(mx) { s.moved(Math.max(0, Math.min(1, mx / width))) }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        onWheel: wheel => s.moved(Math.max(0, Math.min(1, s.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
