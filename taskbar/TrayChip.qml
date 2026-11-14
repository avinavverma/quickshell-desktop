import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick.Effects

// Tray icons. Left click: activate (or menu). Right click: menu. Middle: secondary action.
RowLayout {
    spacing: 14
    readonly property bool available: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        IconImage {
            id: icon
            required property SystemTrayItem modelData
            source: modelData.icon
            implicitSize: 16
            // macOS-style monochrome menu-bar icon
            layer.enabled: true
            layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.fg; brightness: 0.25 }

            MouseArea {
                anchors.fill: parent; anchors.margins: -4
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    const item = icon.modelData
                    if (mouse.button === Qt.MiddleButton) {
                        item.secondaryActivate()
                    } else if (mouse.button === Qt.LeftButton && !item.onlyMenu) {
                        item.activate()
                    } else if (item.hasMenu) {
                        const p = icon.mapToItem(null, 0, 0)
                        item.display(QsWindow.window, p.x, p.y)
                    }
                }
            }
        }
    }
}
