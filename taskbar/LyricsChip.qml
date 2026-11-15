import QtQuick

// Holds the space for the lyric line right after the app icon. The line itself is drawn by
// TopBar.qml, so it can glide from here to the middle of the bar on the desktop.
Item {
    id: root
    readonly property bool available: Lyrics.line !== "" && !(Windows.desktopVisible && Modules.ids("Desktop").includes("desktopmedia"))
    implicitHeight: metrics.height
    implicitWidth: Math.min(metrics.advanceWidth, 440)
    TextMetrics {
        id: metrics
        font.family: Theme.font; font.pixelSize: Theme.fontSize
        text: Lyrics.line
    }
}
