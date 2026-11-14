import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

// Wi-Fi list inside the Control Center. Saved networks connect in one click;
// new ones expand to a password field.
ColumnLayout {
    id: page
    property var dev
    property bool active: false
    property string expanded: ""     // name of the network showing a password field
    spacing: 2

    onActiveChanged: if (!active) expanded = ""

    function strength(n) {
        const s = n?.signalStrength ?? 0
        return s > 1 ? s / 100 : s
    }
    function bars(n) {
        return ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(strength(n) * 4))]
    }

    PageHeader {
        title: "Wi-Fi"
        on: Networking.wifiEnabled
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
    }

    Text {
        visible: Networking.wifiEnabled && list.count === 0
        text: "Looking for networks…"
        color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 12
        Layout.leftMargin: 10; Layout.topMargin: 4; Layout.bottomMargin: 8
    }

    Repeater {
        id: list
        // connected first, then saved, then by signal; hidden (unnamed) networks skipped
        model: Networking.wifiEnabled && page.dev
               ? page.dev.networks.values.filter(n => n.name)
                     .sort((a, b) => (b.connected - a.connected) || (b.known - a.known)
                                     || (page.strength(b) - page.strength(a)))
                     .slice(0, 8)
               : []

        ColumnLayout {
            id: item
            required property var modelData
            readonly property bool open: page.expanded === modelData.name
            Layout.fillWidth: true
            spacing: 4

            PanelRow {
                icon: page.bars(item.modelData)
                title: item.modelData.name
                subtitle: item.modelData.connected ? "Connected"
                        : item.modelData.stateChanging ? "Connecting…"
                        : item.modelData.known ? "Saved" : ""
                trailing: item.modelData.connected ? "󰄬" : ""
                highlighted: item.modelData.connected
                onClicked: {
                    const n = item.modelData
                    if (n.connected) n.disconnect()
                    else if (n.known) n.connect()
                    else page.expanded = item.open ? "" : n.name
                }
            }

            // password for a new network
            RowLayout {
                visible: item.open
                Layout.fillWidth: true
                Layout.leftMargin: 38; Layout.rightMargin: 6; Layout.bottomMargin: 6
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 10
                    color: "#1affffff"
                    border.color: pw.activeFocus ? Theme.accent : "#22ffffff"
                    TextInput {
                        id: pw
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.fg; font.family: Theme.font; font.pixelSize: 12
                        clip: true
                        focus: item.open
                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                        onAccepted: item.join()
                        Text {
                            visible: !pw.text
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: Theme.fgDim; font: pw.font
                        }
                    }
                }
                Rectangle {
                    implicitWidth: 64; implicitHeight: 30; radius: 10
                    color: joinArea.containsMouse ? Qt.lighter(Theme.accent, 1.25) : Theme.accent
                    Text { anchors.centerIn: parent; text: "Join"; color: "white"; font.family: Theme.font; font.pixelSize: 12; font.bold: true }
                    MouseArea { id: joinArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: item.join() }
                }
            }

            function join() {
                if (pw.text) item.modelData.connectWithPsk(pw.text)
                else item.modelData.connect()   // open network
                page.expanded = ""
            }
        }
    }

    PanelRow {
        icon: "󰒓"
        title: "Network Settings…"
        onClicked: { Menus.close(); Quickshell.execDetached(["systemsettings", "kcm_networkmanagement"]) }
    }
}
