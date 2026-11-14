import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Desktop widget: the media card's look, but showing the synced lyrics instead of the
// playback controls. Sits on the desktop (below windows). Three layouts (S / M / L pills at the top
// right) with a fixed number of lyric lines each (3 / 5 / 7), the current line always in the vertical
// middle. Drag the corner grip to scale the current layout up or down - its proportions never change.
// Drag the card anywhere: it snaps to the screen's centre lines and margins (the border lights
// up) and double-click centres it exactly. Position and scale are remembered in
// lyrics-widget.json. Click a line to jump there. Switch it on in Switchboard.
PanelWindow {
    id: win

    // layouts at scale 1: card width, lyric lines shown (odd, so one is in the middle), text size, row height
    readonly property var presets: ({
        S: { w: 380, lines: 3, font: 20, row: 54 },
        M: { w: 460, lines: 5, font: 24, row: 62 },
        L: { w: 560, lines: 7, font: 28, row: 70 }
    })
    property string size: "M"
    readonly property var pr: presets[size] ?? presets.M
    readonly property real headerH: 64
    readonly property real pad: 20
    readonly property real lyricsH: pr.lines * pr.row
    readonly property real baseW: pr.w
    readonly property real baseH: pad * 2 + headerH + 14 + lyricsH
    readonly property real minScale: 0.6
    readonly property real maxScale: Math.max(minScale, Math.min(2.0, (scrW - 48) / baseW, (scrH - 100) / baseH))   // never bigger than the screen
    property real s: 1.0                       // current scale
    readonly property real cardW: baseW * s
    readonly property real cardH: baseH * s

    property real px: 60          // position on the screen
    property real py: 110
    readonly property real scrW: screen?.width ?? 1920
    readonly property real scrH: screen?.height ?? 1080
    property bool snapX: false      // snapped to the horizontal centre while dragging
    property bool snapY: false

    anchors { top: true; left: true }
    margins { left: px; top: py }
    implicitWidth: Math.ceil(cardW)
    implicitHeight: Math.ceil(cardH)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "taskbar-lyrics-widget"
    WlrLayershell.layer: WlrLayer.Bottom
    color: "transparent"
    Item { id: blurBox; width: win.cardW; height: win.cardH }   // real (scaled) size for the blur region
    BackgroundEffect.blurRegion: Region { item: blurBox; radius: 28 * win.s }

    // Switching layout starts at scale 1 and keeps the card's centre where it is.
    function setSize(name) {
        if (name === size || !presets[name]) return
        const oldW = cardW, oldH = cardH
        size = name
        s = 1.0
        px = Math.max(0, Math.min(scrW - cardW, px + (oldW - cardW) / 2))
        py = Math.max(0, Math.min(scrH - cardH, py + (oldH - cardH) / 2))
        saveTimer.restart()
    }

    FileView {
        id: posFile
        path: Qt.resolvedUrl("lyrics-widget.json")
        printErrors: false
        onLoaded: {
            try {
                const o = JSON.parse(text())
                if (typeof o.size === "string" && win.presets[o.size]) win.size = o.size
                if (typeof o.scale === "number") win.s = Math.max(win.minScale, Math.min(win.maxScale, o.scale))
                if (typeof o.x === "number") win.px = o.x
                if (typeof o.y === "number") win.py = o.y
            } catch (e) {}
        }
    }
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: posFile.setText(JSON.stringify({ x: Math.round(win.px), y: Math.round(win.py), size: win.size, scale: Math.round(win.s * 1000) / 1000 }))
    }

    Item {
        id: scaler
        width: win.baseW; height: win.baseH
        scale: win.s
        transformOrigin: Item.TopLeft

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 28
        color: Theme.bg
        border.color: win.snapX || win.snapY ? Theme.accent : Theme.border
        border.width: win.snapX || win.snapY ? 2 : 1
        Behavior on border.color { ColorAnimation { duration: 120 } }

        HoverHandler { id: cardHover }


        // Cover-art glow, as on the media card.
        ClippingRectangle {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
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
            Rectangle { anchors.fill: parent; color: "#40000000" }
        }
        GlassSheen {}

        // Drag the widget by its background / header; snaps to the centre lines and margins.
        MouseArea {
            id: dragArea
            anchors.fill: parent
            readonly property real near: 14
            property point dragStart
            function snap(v, targets) {
                for (const t of targets) if (Math.abs(v - t) < near) return t
                return v
            }
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor
            onPressed: m => { dragStart = mapToItem(null, m.x, m.y) }
            onPositionChanged: m => {
                if (!pressed) return
                // the pointer in screen coordinates (window position + position inside the window),
                // minus where on the card it grabbed
                const p = mapToItem(null, m.x, m.y)
                const rawX = p.x + win.px - dragStart.x
                const rawY = p.y + win.py - dragStart.y
                const cx = (win.scrW - win.cardW) / 2, cy = (win.scrH - win.cardH) / 2
                const nx = snap(rawX, [cx, 24, win.scrW - win.cardW - 24])
                const ny = snap(rawY, [cy, 52, win.scrH - win.cardH - 24])
                win.snapX = nx === cx
                win.snapY = ny === cy
                win.px = Math.max(0, nx)
                win.py = Math.max(0, ny)
            }
            onReleased: { win.snapX = false; win.snapY = false; saveTimer.restart() }
            onDoubleClicked: {      // exactly centred on the screen
                win.px = (win.scrW - win.cardW) / 2
                win.py = (win.scrH - win.cardH) / 2
                saveTimer.restart()
            }
        }

        // "Centered" hint while snapped to a centre line.
        Rectangle {
            z: 10
            visible: win.snapX || win.snapY
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
            width: hint.implicitWidth + 18; height: hint.implicitHeight + 8; radius: height / 2
            color: Theme.accent
            Text {
                id: hint
                anchors.centerIn: parent
                text: win.snapX && win.snapY ? "Centered" : win.snapX ? "Centered horizontally" : "Centered vertically"
                color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }

        // Resize grip (bottom-right): scales the whole card, keeping its proportions.
        MouseArea {
            id: grip
            z: 20
            width: 34; height: 34
            anchors { right: parent.right; bottom: parent.bottom }
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property real offX
            property real startW
            // pointer in window coordinates; the window's top-left is fixed, so the target only
            // depends on where the pointer is - no feedback while the window catches up
            onPressed: m => { const p = mapToItem(null, m.x, m.y); startW = win.cardW; offX = p.x - win.cardW }
            onPositionChanged: m => {
                if (!pressed) return
                const p = mapToItem(null, m.x, m.y)
                win.s = Math.max(win.minScale, Math.min(win.maxScale, (p.x - offX) / win.baseW))
            }
            onReleased: saveTimer.restart()
            Canvas {
                anchors.fill: parent
                opacity: grip.containsMouse || grip.pressed ? 0.9 : cardHover.hovered ? 0.4 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                onPaint: {
                    const c = getContext("2d"); c.reset()
                    c.strokeStyle = "white"; c.lineWidth = 1.8; c.lineCap = "round"
                    c.beginPath(); c.moveTo(width - 8, height - 20); c.lineTo(width - 20, height - 8); c.stroke()
                    c.beginPath(); c.moveTo(width - 8, height - 13); c.lineTo(width - 13, height - 8); c.stroke()
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: win.pad
            spacing: 14

            // Header: cover + title / artist, like the media card; size pills at the right.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: win.headerH
                spacing: 14
                ClippingRectangle {
                    Layout.preferredWidth: 64; Layout.preferredHeight: 64
                    radius: 12
                    color: "#22ffffff"
                    border.width: 1; border.color: "#26ffffff"
                    Image {
                        anchors.fill: parent
                        source: NowPlaying.artFile
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 160; sourceSize.height: 160
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: NowPlaying.openPlayer() }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: NowPlaying.player ? NowPlaying.title : "Nothing playing"
                        color: Theme.fg; font.family: Theme.font
                        font.pixelSize: 17; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [NowPlaying.player?.trackArtist || NowPlaying.artist, NowPlaying.album].filter(s => s).join("  ·  ")
                        color: Qt.rgba(1, 1, 1, 0.62); font.family: Theme.font; font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
                // S / M / L
                Row {
                    Layout.alignment: Qt.AlignTop
                    spacing: 2
                    opacity: cardHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Repeater {
                        model: ["S", "M", "L"]
                        Rectangle {
                            required property string modelData
                            readonly property bool on: win.size === modelData
                            width: 24; height: 20; radius: 10
                            color: on ? "#40ffffff" : sizeArea.containsMouse ? "#22ffffff" : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.on ? Theme.fg : Qt.rgba(1, 1, 1, 0.55)
                                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: sizeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.setSize(parent.modelData)
                            }
                        }
                    }
                }
            }

            // Lyrics: a fixed number of rows, the current line always in the middle row.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: win.lyricsH
                clip: true

                ListView {
                    id: list
                    anchors.fill: parent
                    visible: Lyrics.lines.length > 0
                    model: Lyrics.lines
                    interactive: false
                    readonly property real mid: (height - win.pr.row) / 2
                    topMargin: mid
                    bottomMargin: mid
                    currentIndex: Math.max(0, Lyrics.lineIndex)
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: mid
                    preferredHighlightEnd: mid + win.pr.row
                    highlightMoveDuration: 450
                    highlightMoveVelocity: -1

                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property int dist: Math.abs(index - Lyrics.lineIndex)
                        readonly property bool current: dist === 0
                        width: list.width
                        height: win.pr.row

                        Text {
                            id: label
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 6
                            height: parent.height - 6
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.text === "" ? "♪" : row.modelData.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            fontSizeMode: Text.Fit            // long lines shrink a little instead of overflowing
                            minimumPixelSize: Math.round(win.pr.font * 0.7)
                            color: Theme.fg
                            font.family: Theme.font; font.pixelSize: win.pr.font; font.weight: Font.Bold
                            transformOrigin: Item.Left
                            scale: row.current ? 1 : 0.84
                            opacity: row.current ? 1 : row.dist === 1 ? 0.5 : row.dist === 2 ? 0.34 : 0.22
                            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 280 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Lyrics.pp?.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (Lyrics.pp?.canSeek) Lyrics.pp.position = row.modelData.t
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: Lyrics.lines.length === 0
                    text: !NowPlaying.player ? "Nothing playing"
                          : Lyrics.loading ? "Looking for lyrics…"
                          : !Lyrics.pp ? "No timing from this player"
                          : "No synced lyrics for this song"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.family: Theme.font; font.pixelSize: 15
                }
            }
        }
    }
    }
}

