import QtQuick
import QtQuick.Layouts
import Quickshell

// Bluetooth list inside the Control Center: paired devices, click to connect/disconnect.
ColumnLayout {
    id: page
    property var adapter
    readonly property bool on: adapter?.enabled ?? false
    readonly property var paired: adapter
        ? adapter.devices.values.filter(d => d.paired || d.connected)
              .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || ""))
        : []
    spacing: 2

    function deviceIcon(d) {
        const i = d.icon ?? ""
        if (/headset|headphone|audio/.test(i)) return "󰋋"
        if (/mouse/.test(i)) return "󰍽"
        if (/keyboard/.test(i)) return "󰌌"
        if (/phone/.test(i)) return "󰏲"
        if (/game|joystick/.test(i)) return "󰊴"
        return "󰂯"
    }

    PageHeader {
        title: "Bluetooth"
        on: page.on
        onToggled: if (page.adapter) page.adapter.enabled = !page.adapter.enabled
    }

    Text {
        visible: page.on && page.paired.length === 0
        text: "No paired devices"
        color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 12
        Layout.leftMargin: 10; Layout.topMargin: 4; Layout.bottomMargin: 8
    }

    Repeater {
        model: page.on ? page.paired : []
        PanelRow {
            required property var modelData
            icon: page.deviceIcon(modelData)
            title: modelData.name || modelData.address
            subtitle: modelData.connected ? "Connected" : modelData.pairing ? "Pairing…" : "Not connected"
            trailing: modelData.connected && modelData.batteryAvailable
                      ? `${Math.round(modelData.battery <= 1 ? modelData.battery * 100 : modelData.battery)}%` : ""
            highlighted: modelData.connected
            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
        }
    }

    PanelRow {
        icon: "󰒓"
        title: "Bluetooth Settings…"
        onClicked: { Menus.close(); Quickshell.execDetached(["systemsettings", "kcm_bluetooth"]) }
    }
}
