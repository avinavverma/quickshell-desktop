import QtQuick

// The line being sung, right after the app icon; changes with a quick fade + slide.
Item {
    id: root
    readonly property bool available: Lyrics.line !== ""
    implicitHeight: label.implicitHeight
    implicitWidth: label.width

    property string shown: ""
    Connections {
        target: Lyrics
        function onLineChanged() { if (Lyrics.line !== "") swap.restart(); else root.shown = "" }
    }
    Component.onCompleted: shown = Lyrics.line

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 0; duration: 80 }
            NumberAnimation { target: label; property: "yOff"; to: 4; duration: 80 }
        }
        ScriptAction { script: { root.shown = Lyrics.line; label.yOff = -4 } }
        ParallelAnimation {
            NumberAnimation { target: label; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { target: label; property: "yOff"; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Text {
        id: label
        property real yOff: 0
        text: root.shown
        color: Theme.fg
        font.family: Theme.font; font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 440)
        y: yOff
    }
}
