import QtQuick
import Quickshell

Text {
    readonly property bool available: true
    SystemClock { id: clock; precision: SystemClock.Minutes }
    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
    color: Theme.fg
    font.family: Theme.font; font.pixelSize: Theme.fontSize; font.weight: Font.Medium
}
