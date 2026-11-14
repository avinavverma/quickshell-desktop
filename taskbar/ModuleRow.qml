import QtQuick
import QtQuick.Layouts

// A row of modules (by id) with thin dividers between them.
RowLayout {
    id: root
    property var ids: []
    property bool mediaHovered: false
    property bool dividers: true     // thin lines between modules
    property bool hoverPills: false  // macOS-style rounded highlight behind the hovered item
    spacing: Theme.moduleSpacing

    Repeater {
        model: root.ids

        RowLayout {
            id: slot
            required property string modelData
            required property int index
            spacing: Theme.moduleSpacing
            visible: loader.item?.available ?? false

            Rectangle {
                visible: root.dividers && slot.index > 0
                implicitWidth: 1; implicitHeight: 16
                color: Theme.divider
            }
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: loader.implicitWidth
                implicitHeight: loader.implicitHeight
                Rectangle {   // hover pill
                    anchors.fill: parent
                    anchors.margins: -5
                    anchors.leftMargin: -7; anchors.rightMargin: -7
                    radius: 7
                    color: "#26ffffff"
                    opacity: root.hoverPills && cellHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                HoverHandler { id: cellHover }
                Loader {
                    id: loader
                                    sourceComponent: ({
                        launcher: launcherModule,
                        media: mediaModule, clock: clockModule, volume: volumeModule,
                        battery: batteryModule, tray: trayModule,
                        wifi: wifiModule, bluetooth: bluetoothModule,
                        window: windowModule, appname: appNameModule, lyrics: lyricsModule, controls: controlsModule
                    })[slot.modelData] ?? null
                }
            }
        }
    }

    Component { id: launcherModule; LauncherChip {} }
    Component { id: mediaModule;    MediaChip { onHoveredChanged: root.mediaHovered = hovered } }
    Component { id: clockModule;    ClockChip {} }
    Component { id: volumeModule;   VolumeChip {} }
    Component { id: batteryModule;  BatteryChip {} }
    Component { id: trayModule;     TrayChip {} }
    Component { id: wifiModule;     WifiChip {} }
    Component { id: bluetoothModule; BluetoothChip {} }
    Component { id: windowModule;   WindowChip {} }
    Component { id: appNameModule;  AppNameChip {} }
    Component { id: lyricsModule;   LyricsChip {} }
    Component { id: controlsModule; ControlChip {} }
}
