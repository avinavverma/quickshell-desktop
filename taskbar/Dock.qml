import QtQuick

// macOS-style dock: frosted rounded shelf that widens as icons magnify.
Item {
    id: dock
    readonly property real radius: 20
    readonly property bool hovered: hover.hovered
    property bool shown: true   // set by the dock window (auto-hide)

    width: apps.implicitWidth + 16
    height: Theme.dockHeight

    HoverHandler { id: hover }

    // the shelf (magnified icons rise above it)
    Rectangle {
        anchors.fill: parent
        radius: dock.radius
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        GlassSheen {}
    }

    DockApps {
        id: apps
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (Theme.dockHeight - Theme.dockSlot) / 2
    }
}
