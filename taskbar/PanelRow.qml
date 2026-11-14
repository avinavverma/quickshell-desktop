import QtQuick
import QtQuick.Layouts

// One clickable row in a menu: icon, title, optional subtitle and trailing text.
Rectangle {
    id: row
    property string icon
    property string title
    property string subtitle
    property string trailing
    property bool highlighted: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: subtitle ? 46 : 36
    radius: 12
    color: highlighted ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : area.containsMouse ? "#14ffffff" : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 10

        Text {
            text: row.icon
            color: row.highlighted ? Theme.accent : Theme.fg
            font.family: Theme.font; font.pixelSize: 16
            Layout.preferredWidth: 18
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: row.title
                color: Theme.fg; font.family: Theme.font; font.pixelSize: 13
                font.bold: row.highlighted
                elide: Text.ElideRight; Layout.fillWidth: true
            }
            Text {
                visible: row.subtitle !== ""
                text: row.subtitle
                color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 11
                elide: Text.ElideRight; Layout.fillWidth: true
            }
        }
        Text {
            visible: row.trailing !== ""
            text: row.trailing
            color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 12
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
