import QtQuick

// Full-width menu bar flush with the top edge: left / center / right sections.
Rectangle {
    id: top
    readonly property bool mediaHovered: left.mediaHovered || center.mediaHovered || right.mediaHovered

    height: Theme.barHeight
    color: Theme.barTint   // transparent-ish, macOS 26 style (no glass, no outline)

    ModuleRow {
        id: left
        anchors { left: parent.left; leftMargin: Theme.barPad; verticalCenter: parent.verticalCenter }
        ids: Modules.ids("Top bar", "left")
        dividers: false; hoverPills: true
    }
    ModuleRow {
        id: center
        anchors.centerIn: parent
        ids: Modules.ids("Top bar", "center")
        dividers: false
        // on the desktop the lyric line takes the middle (the media card below shows the song)
        opacity: top.lyricsCentered ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.InOutCubic } }
    }
    ModuleRow {
        id: right
        anchors { right: parent.right; rightMargin: Theme.barPad; verticalCenter: parent.verticalCenter }
        ids: Modules.ids("Top bar", "right")
        dividers: false; hoverPills: true
        spacing: 20
    }

    // ---------- the lyric line ----------
    // Normally right after the app icon (the "lyrics" module there only holds the space); on the
    // desktop it glides to the middle of the bar while the media chip fades out.
    readonly property bool lyricsOn: left.ids.indexOf("lyrics") >= 0
    readonly property bool lyricsCentered: lyricsOn && Windows.desktopVisible && Lyrics.line !== ""
        && Modules.ids("Desktop").includes("desktopmedia")      // Switchboard option
    readonly property bool appIconShown: left.ids.indexOf("appname") >= 0
        && left.ids.indexOf("appname") < left.ids.indexOf("lyrics")
        && Windows.list.some(w => w.active && !w.minimized)
    readonly property real lyricsLeftX: left.x + (appIconShown ? 20 + left.spacing : 0)

    Item {
        id: lyric
        visible: top.lyricsOn
        height: parent.height
        width: label.width
        // 0 = after the app icon, 1 = centred. Only this glides; a new line's width re-centres it
        // instantly (it changes while the old line is faded out), so lines appear right in the middle.
        property real mode: top.lyricsCentered ? 1 : 0
        Behavior on mode { NumberAnimation { duration: top.lyricsCentered ? 520 : 260; easing.type: Easing.InOutCubic } }
        x: top.lyricsLeftX * (1 - mode) + (top.width - width) / 2 * mode
        opacity: Lyrics.line !== "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        property string shown: ""
        Connections {
            target: Lyrics
            function onLineChanged() { if (Lyrics.line !== "") swap.restart() }
        }
        Component.onCompleted: shown = Lyrics.line

        SequentialAnimation {
            id: swap
            ParallelAnimation {
                NumberAnimation { target: label; property: "opacity"; to: 0; duration: 80 }
                NumberAnimation { target: label; property: "yOff"; to: 4; duration: 80 }
            }
            ScriptAction { script: { lyric.shown = Lyrics.line; label.yOff = -4 } }
            ParallelAnimation {
                NumberAnimation { target: label; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: label; property: "yOff"; to: 0; duration: 180; easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: label
            property real yOff: 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: yOff
            text: lyric.shown
            color: Theme.fg
            font.family: Theme.font; font.pixelSize: Theme.fontSize
            elide: Text.ElideRight
            width: Math.min(implicitWidth, top.lyricsCentered ? 760 : 440)
        }
    }
}
