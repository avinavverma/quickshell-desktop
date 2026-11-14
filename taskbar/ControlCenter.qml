import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Widgets

// macOS-style Control Center. Always loaded; opening it is just an animation.
// Pages slide sideways: main tiles <-> Wi-Fi list / Bluetooth list.
Rectangle {
    id: cc
    readonly property bool shown: Menus.open === "control"
    readonly property int pad: 12
    readonly property int innerW: width - pad * 2
    readonly property int half: (innerW - 10) / 2

    // shared state
    readonly property var wifiDev: Networking.devices.values.find(d => d.scannerEnabled !== undefined) ?? null
    readonly property var wifiNet: wifiDev ? wifiDev.networks.values.find(n => n.connected) ?? null : null
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btConnected: bt ? bt.devices.values.filter(d => d.connected) : []
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var player: NowPlaying.player
    PwObjectTracker { objects: [cc.sink] }

    width: 340
    height: (Menus.page === "main" ? mainPage.implicitHeight
           : Menus.page === "wifi" ? wifiPage.implicitHeight : btPage.implicitHeight) + pad * 2
    x: Math.max(Theme.gap, Math.min(Menus.anchorX - width / 2, parent.width - width - Theme.gap))
    y: Theme.barHeight + 6
    radius: 24
    color: Theme.bg
    border.color: Theme.border
    border.width: 1
    clip: true

    // open/close animation
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.96
    transformOrigin: Item.Top
    visible: opacity > 0
    transform: Translate { y: cc.shown ? 0 : -8; Behavior on y { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } } }
    Behavior on opacity { NumberAnimation { duration: cc.shown ? 150 : 110; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // Scan for Wi-Fi networks only while the Wi-Fi page is up.
    Binding { target: cc.wifiDev; property: "scannerEnabled"; value: cc.shown && Menus.page === "wifi"; when: cc.wifiDev !== null }

    GlassSheen {}
    MouseArea { anchors.fill: parent }   // keep clicks from reaching the click-outside catcher

    // ===================== main page =====================
    ColumnLayout {
        id: mainPage
        x: Menus.page === "main" ? cc.pad : -cc.width
        y: cc.pad
        width: cc.innerW
        spacing: 10
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // --- top block: connectivity | (Do Not Disturb, Night Light + Screenshot) ---
        RowLayout {
            spacing: 10
            Layout.fillWidth: true

            Tile {
                Layout.preferredWidth: cc.half
                Layout.preferredHeight: 126
                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 6
                    ConnRow {
                        icon: Networking.wifiEnabled ? "󰤨" : "󰤭"
                        on: Networking.wifiEnabled
                        title: "Wi-Fi"
                        subtitle: !Networking.wifiEnabled ? "Off" : cc.wifiNet?.name ?? "Not connected"
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                        onOpened: Menus.page = "wifi"
                    }
                    ConnRow {
                        icon: "󰂯"
                        on: cc.bt?.enabled ?? false
                        title: "Bluetooth"
                        subtitle: !(cc.bt?.enabled ?? false) ? "Off"
                                : cc.btConnected.length === 1 ? cc.btConnected[0].name
                                : cc.btConnected.length > 1 ? `${cc.btConnected.length} devices` : "On"
                        onToggled: if (cc.bt) cc.bt.enabled = !cc.bt.enabled
                        onOpened: Menus.page = "bluetooth"
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: cc.half
                spacing: 10

                Tile {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8
                        CircleButton { icon: "󰂛"; on: System.dnd; onClicked: System.toggleDnd() }
                        ColumnLayout {
                            spacing: 0; Layout.fillWidth: true
                            Text { text: "Do Not Disturb"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: System.dnd ? "On" : "Off"; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                }
                RowLayout {
                    spacing: 10
                    SmallTile { icon: "󰖔"; label: "Night Light"; on: System.nightLight; onClicked: System.toggleNightLight() }
                    SmallTile {
                        icon: "󰹑"; label: "Screenshot"
                        onClicked: { Menus.close(); Quickshell.execDetached(["spectacle", "-r"]) }
                    }
                }
            }
        }

        // --- Display ---
        Tile {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 6
                Text { text: "Display"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.bold: true }
                CCSlider {
                    Layout.fillWidth: true
                    icon: "󰃠"
                    value: System.brightness
                    onMoved: v => System.setBrightness(v)
                }
            }
        }

        // --- Sound ---
        Tile {
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 6
                Text { text: "Sound"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.bold: true }
                CCSlider {
                    Layout.fillWidth: true
                    icon: (cc.sink?.audio?.muted ?? false) ? "󰝟" : "󰕾"
                    value: cc.sink?.audio?.muted ? 0 : (cc.sink?.audio?.volume ?? 0)
                    onMoved: v => { if (cc.sink) { cc.sink.audio.muted = false; cc.sink.audio.volume = v } }
                }
            }
        }

        // --- Now Playing ---
        Tile {
            visible: cc.player !== null
            Layout.fillWidth: true
            Layout.preferredHeight: 62
            RowLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 10
                ClippingRectangle {
                    Layout.preferredWidth: 42; Layout.preferredHeight: 42
                    radius: 8
                    color: "#22ffffff"
                    Image {
                        anchors.fill: parent
                        source: NowPlaying.artFile
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 128; sourceSize.height: 128
                    }
                }
                ColumnLayout {
                    spacing: 0; Layout.fillWidth: true
                    Text { text: NowPlaying.title; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: NowPlaying.artist; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                Glyph { icon: cc.player?.isPlaying ? "󰏤" : "󰐊"; onClicked: cc.player.togglePlaying() }
                Glyph { icon: "󰒭"; onClicked: cc.player.next() }
            }
        }
    }

    // ===================== Wi-Fi page =====================
    WifiPage {
        id: wifiPage
        x: Menus.page === "wifi" ? cc.pad : cc.width
        y: cc.pad
        width: cc.innerW
        dev: cc.wifiDev
        active: cc.shown && Menus.page === "wifi"
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // ===================== Bluetooth page =====================
    BluetoothPage {
        id: btPage
        x: Menus.page === "bluetooth" ? cc.pad : cc.width
        y: cc.pad
        width: cc.innerW
        adapter: cc.bt
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    // ---------- small pieces ----------
    // A row in the connectivity tile: round toggle + name; clicking the name opens its list.
    component ConnRow: RowLayout {
        id: r
        property string icon
        property bool on
        property string title
        property string subtitle
        signal toggled()
        signal opened()
        spacing: 8
        Layout.fillWidth: true
        CircleButton { icon: r.icon; on: r.on; onClicked: r.toggled() }
        Item {
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight
            ColumnLayout {
                id: col
                width: parent.width
                spacing: 0
                Text { text: r.title; color: Theme.fg; font.family: Theme.font; font.pixelSize: 12; font.bold: true }
                Text { text: r.subtitle; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: r.opened() }
        }
        Text { text: "󰅂"; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 14
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: r.opened() } }
    }

    // Square tile: round icon over a label.
    component SmallTile: Tile {
        id: st
        property string icon
        property string label
        property bool on: false
        signal clicked()
        Layout.preferredWidth: (cc.half - 10) / 2
        Layout.preferredHeight: 58
        Column {
            anchors.centerIn: parent
            spacing: 4
            CircleButton { anchors.horizontalCenter: parent.horizontalCenter; size: 26; icon: st.icon; on: st.on; onClicked: st.clicked() }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: st.label; color: Theme.fg; font.family: Theme.font; font.pixelSize: 9 }
        }
    }

    component Glyph: Text {
        property string icon
        signal clicked()
        text: icon
        color: ga.containsMouse ? Theme.accent : Theme.fg
        font.family: Theme.font; font.pixelSize: 18
        MouseArea { id: ga; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
}
