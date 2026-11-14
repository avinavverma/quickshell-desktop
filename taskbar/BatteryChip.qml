import QtQuick
import Quickshell.Services.UPower

// Battery icon; the percentage slides out to its left only while you hover it.
// Hidden on machines without a laptop battery.
Row {
    id: root
    readonly property var dev: UPower.displayDevice
    // UPower reports either 0-1 or 0-100 depending on version; handle both.
    readonly property int pct: Math.round(dev.percentage <= 1 ? dev.percentage * 100 : dev.percentage)
    readonly property bool charging: !UPower.onBattery
    readonly property var levels: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

    readonly property bool available: dev.isLaptopBattery
    spacing: 0

    HoverHandler { id: hover }

    Item {   // percentage, first like macOS; zero width (so the bar doesn't shift) until hovered
        id: pctBox
        anchors.verticalCenter: parent.verticalCenter
        height: pctText.implicitHeight
        width: hover.hovered ? pctText.implicitWidth + 6 : 0
        clip: true
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Text {
            id: pctText
            anchors.verticalCenter: parent.verticalCenter
            text: `${root.pct}%`
            color: Theme.fg
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.charging ? "󰂄" : root.levels[Math.min(9, Math.floor(root.pct / 10))]
        color: !root.charging && root.pct <= 15 ? Theme.accent : Theme.fg
        font.family: Theme.iconFont; font.pixelSize: 17
    }
}
