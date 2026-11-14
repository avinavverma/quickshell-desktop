import QtQuick
import Quickshell.Services.Pipewire

// Speaker volume. Scroll to change, click to mute.
Text {
    id: root
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real vol: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    PwObjectTracker { objects: [root.sink] }

    readonly property bool available: sink !== null
    // Icon only (scroll to change, click to mute); level shows in the icon.
    text: muted ? "󰝟" : vol > 0.66 ? "󰕾" : vol > 0.33 ? "󰖀" : "󰕿"
    color: muted ? Theme.fgDim : Theme.fg
    font.family: Theme.iconFont; font.pixelSize: 16

    MouseArea {
        id: area
        anchors.fill: parent; anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.sink.audio.muted = !root.muted
        onWheel: wheel => {
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            root.sink.audio.volume = Math.max(0, Math.min(1, root.vol + step))
        }
    }
}
