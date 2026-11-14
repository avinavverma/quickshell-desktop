import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets

// The big player that drops down below the top bar while the media chip is hovered.
Rectangle {
    id: card
    property bool open: false
    readonly property bool hovered: hover.hovered
    readonly property var player: NowPlaying.player
    // Stay open briefly after the pointer leaves, so it can travel from chip to card.
    readonly property bool shown: (open || closeDelay.running) && player !== null

    onOpenChanged: if (!open) closeDelay.restart()
    Timer { id: closeDelay; interval: 250 }

    TextMetrics { id: titleMetrics; font: titleText.font; text: titleText.text }      // full, un-elided text widths
    TextMetrics { id: artistMetrics; font: artistLine.font; text: artistLine.text }
    // As wide as the title / artist need (never narrower than the usual card, never wider than 1000).
    readonly property real wanted: 18 * 2 + 112 + 18 + Math.max(titleMetrics.advanceWidth, artistMetrics.advanceWidth) * 1.08 + 28
    width: Math.max(Theme.cardWidth, Math.min(1000, wanted))
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    height: Theme.cardHeight
    radius: 28
    color: Theme.bg
    border.color: Theme.border
    border.width: 1

    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    transformOrigin: Item.Top
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim / 1.5 } }
    Behavior on scale { NumberAnimation { duration: Theme.anim; easing.type: Easing.OutBack } }

    // Apple-Music-style ambience: the cover art, blurred and saturated, glowing through the glass.
    ClippingRectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        visible: card.shown
        Image {
            id: glow
            anchors.fill: parent
            source: NowPlaying.artFile
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 48; sourceSize.height: 48
            smooth: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            anchors.margins: -30
            source: glow
            blurEnabled: true; blurMax: 64; blur: 1.0
            saturation: 0.5; brightness: -0.12
            opacity: 0.5
        }
        Rectangle {   // keeps the text readable
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#59000000" }
            }
        }
    }
    GlassSheen {}
    HoverHandler { id: hover }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 18

        Item {
            id: coverBox
            Layout.preferredWidth: 112; Layout.preferredHeight: 112
            Layout.alignment: Qt.AlignVCenter
            property real coverScale: card.player?.isPlaying ? 1.0 : 0.9
            Behavior on coverScale { SpringAnimation { spring: 4; damping: 0.55; epsilon: 0.002 } }
            transform: Scale { origin.x: coverBox.width / 2; origin.y: coverBox.height / 2; xScale: coverBox.coverScale; yScale: coverBox.coverScale }

            RectangularShadow {
                anchors.fill: parent
                radius: 14
                blur: 26; spread: -2
                offset: Qt.vector2d(0, 8)
                color: Qt.rgba(0, 0, 0, 0.55)
            }
            ClippingRectangle {
                anchors.fill: parent
                radius: 14
                color: "#22ffffff"
                border.width: 1; border.color: "#26ffffff"
                Image {
                    anchors.fill: parent
                    source: NowPlaying.artFile
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 256; sourceSize.height: 256
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                id: titleText
                text: NowPlaying.title
                color: Theme.fg; font.family: Theme.font
                font.pixelSize: 17; font.weight: Font.DemiBold
                elide: Text.ElideRight; Layout.fillWidth: true
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
            }
            Text {
                id: artistLine
                text: [card.player?.trackArtist || NowPlaying.artist, NowPlaying.album].filter(s => s).join("  ·  ")
                color: Qt.rgba(1, 1, 1, 0.62); font.family: Theme.font; font.pixelSize: 13
                elide: Text.ElideRight; Layout.fillWidth: true
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
            }

            // Progress: smooth, click/drag to seek, elapsed / remaining underneath.
            Item {
                id: progress
                readonly property var src: NowPlaying.progressPlayer   // may differ from card.player (see NowPlaying)
                readonly property real len: src?.length ?? 0
                // Only when the player really reports a length (Apple Music in Firefox,
                // without the Plasma Browser Integration add-on, reports none and a
                // position stuck at 0 - showing a bar then would just be wrong).
                readonly property bool known: src !== null && len > 0
                readonly property bool trusted: NowPlaying.lengthTrusted   // else: elapsed time only
                readonly property bool seekable: known && trusted && (src?.canSeek ?? false)
                property real dragFrac: -1   // while dragging, show where you're pointing
                readonly property real frac: dragFrac >= 0 ? dragFrac
                    : known && trusted ? Math.max(0, Math.min(1, (src?.position ?? 0) / len)) : 0
                function fmt(s) {
                    s = Math.max(0, Math.round(s))
                    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
                }

                visible: known
                Layout.fillWidth: true; Layout.topMargin: 6
                implicitHeight: 22

                Rectangle {   // track
                    id: track
                    visible: progress.trusted
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: seekArea.containsMouse || seekArea.pressed ? 6 : 4
                    radius: height / 2
                    color: "#33ffffff"
                    Behavior on height { NumberAnimation { duration: 100 } }
                    Rectangle {
                        height: parent.height; radius: parent.radius
                        color: Theme.fg
                        width: parent.width * progress.frac
                    }
                }
                Text {
                    anchors { left: parent.left; bottom: parent.bottom }
                    text: progress.trusted ? progress.fmt(progress.frac * progress.len)
                                           : progress.fmt(progress.src?.position ?? 0)
                    color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 10
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom }
                    visible: progress.trusted
                    text: "-" + progress.fmt((1 - progress.frac) * progress.len)
                    color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 10
                }
                MouseArea {
                    id: seekArea
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 14; anchors.topMargin: -5
                    enabled: progress.seekable
                    hoverEnabled: true
                    cursorShape: progress.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    function fracAt(x) { return Math.max(0, Math.min(1, x / width)) }
                    onPressed: mouse => progress.dragFrac = fracAt(mouse.x)
                    onPositionChanged: mouse => { if (pressed) progress.dragFrac = fracAt(mouse.x) }
                    onReleased: mouse => {
                        progress.src.position = fracAt(mouse.x) * progress.len
                        progress.dragFrac = -1
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 30
                Glyph { icon: "󰒮"; size: 24; active: card.player?.canGoPrevious ?? false; onClicked: card.player.previous() }
                Glyph { icon: card.player?.isPlaying ? "󰏤" : "󰐊"; size: 32; onClicked: card.player.togglePlaying() }
                Glyph { icon: "󰒭"; size: 24; active: card.player?.canGoNext ?? false; onClicked: card.player.next() }
            }
        }
    }

    component Glyph: Text {
        property string icon
        property int size: 16
        property bool active: true
        signal clicked()
        text: icon
        color: !active ? Theme.fgDim : mouse.containsMouse ? Theme.accent : Theme.fg
        font.family: Theme.font; font.pixelSize: size
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: mouse.pressed ? 0.82 : mouse.containsMouse ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        MouseArea {
            id: mouse
            anchors.fill: parent; anchors.margins: -6
            enabled: parent.active
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}

