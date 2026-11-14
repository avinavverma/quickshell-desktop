import QtQuick
import QtQuick.Layouts

// Header of a Control Center detail page: back arrow, title, on/off switch.
RowLayout {
    id: header
    property string title
    property bool on
    signal toggled()

    Layout.fillWidth: true
    Layout.bottomMargin: 6
    spacing: 6

    Rectangle {
        implicitWidth: 28; implicitHeight: 28; radius: 14
        color: back.containsMouse ? "#2affffff" : "transparent"
        Text { anchors.centerIn: parent; text: "󰅁"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 16 }
        MouseArea { id: back; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Menus.page = "main" }
    }
    Text {
        text: header.title
        color: Theme.fg; font.family: Theme.font; font.pixelSize: 15; font.bold: true
        Layout.fillWidth: true
    }
    Toggle { on: header.on; onToggled: header.toggled() }
}
