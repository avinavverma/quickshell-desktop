import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// Compact now-playing: art, "title · artist", play/pause. Hover opens the MediaCard.
RowLayout {
    id: root
    readonly property var player: NowPlaying.player
    readonly property bool hovered: hover.hovered
    readonly property bool available: true
    spacing: 8

    HoverHandler { id: hover }

    ClippingRectangle {
        visible: root.player !== null
        Layout.preferredWidth: 24; Layout.preferredHeight: 24
        radius: 12
        color: "#22ffffff"
        Image {
            anchors.fill: parent
            source: NowPlaying.artFile
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 64; sourceSize.height: 64
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
    }

    Text {
        text: root.player
              ? [NowPlaying.title || "Unknown", NowPlaying.artist].filter(s => s).join("  ·  ")
              : "󰝛  Nothing playing"
        color: root.player ? Theme.fg : Theme.fgDim
        font.family: Theme.font; font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
        Layout.maximumWidth: 900      // effectively no limit; only a truly huge title ends in "…"
        MouseArea { anchors.fill: parent; enabled: root.player !== null; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
    }

    Text {
        visible: root.player !== null
        text: root.player?.isPlaying ? "󰏤" : "󰐊"
        color: playArea.containsMouse ? Theme.accent : Theme.fg
        font.family: Theme.font; font.pixelSize: 16
        MouseArea {
            id: playArea
            anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.player.togglePlaying()
        }
    }
}
