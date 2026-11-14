import QtQuick
import QtQuick.Layouts
import Quickshell

// Right-click menu for a dock icon (macOS style), shown above the icon.
Rectangle {
    id: menu
    readonly property bool shown: Menus.open === "dock" && Menus.dockEntry !== null
    readonly property var e: Menus.dockEntry
    readonly property bool isApp: e?.kind === "app"
    readonly property bool running: (e?.windows?.length ?? 0) > 0

    width: Math.max(200, body.implicitWidth + 16)
    height: body.implicitHeight + 12
    x: Math.max(Theme.gap, Math.min(Menus.dockX - width / 2, parent.width - width - Theme.gap))
    y: Menus.dockY - height - 10
    radius: 12
    color: Theme.bgSolid
    border.color: Theme.border
    border.width: 1

    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.95
    transformOrigin: Item.Bottom
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: menu.shown ? 120 : 90 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    GlassSheen {}
    MouseArea { anchors.fill: parent }   // keep clicks off the click-outside catcher

    function act(f) { Menus.close(); f() }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
        spacing: 0

        // --- the app's windows ---
        Repeater {
            model: menu.isApp ? (menu.e?.windows ?? []) : []
            Item_ {
                required property var modelData
                text: modelData.title
                checked: modelData.active
                onClicked: menu.act(() => Windows.focus(modelData.id))
            }
        }
        Sep { visible: menu.isApp && menu.running }

        // --- app actions ---
        Item_ {
            visible: menu.isApp
            text: "Keep in Dock"
            checked: menu.e?.pinned ?? false
            onClicked: { const e = menu.e; menu.act(() => e.pinned ? Windows.unpin(e.id) : Windows.pin(e.id)) }
        }
        Item_ {
            visible: menu.isApp
            text: menu.running ? "New Window" : "Open"
            onClicked: { const id = menu.e.id; menu.act(() => Windows.launch(id)) }
        }
        Sep { visible: menu.isApp && menu.running }
        Item_ {
            visible: menu.isApp && menu.running
            text: "Quit"
            onClicked: { const id = menu.e.id; menu.act(() => Windows.quit(id)) }
        }

        // --- launcher ---
        Item_ {
            visible: menu.e?.kind === "launcher"
            text: "Search Apps"
            onClicked: menu.act(() => Quickshell.execDetached(["qdbus6", "org.kde.krunner", "/App", "display"]))
        }
        Item_ {
            visible: menu.e?.kind === "launcher"
            text: "Show All Windows"
            onClicked: menu.act(() => Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel", "/component/kwin", "invokeShortcut", "Overview"]))
        }

        // --- minimised window ---
        Item_ {
            visible: menu.e?.kind === "min"
            text: "Restore"
            onClicked: { const id = menu.e.id; menu.act(() => Windows.focus(id)) }
        }
        Item_ {
            visible: menu.e?.kind === "min"
            text: "Close"
            onClicked: { const id = menu.e.id; menu.act(() => Windows.close(id)) }
        }

        // --- Trash ---
        Item_ {
            visible: menu.e?.kind === "trash"
            text: "Open"
            onClicked: menu.act(() => Windows.trash("open"))
        }
        Item_ {
            visible: menu.e?.kind === "trash"
            text: "Empty Trash"
            enabled: Windows.trashFull
            onClicked: menu.act(() => Windows.trash("empty"))
        }
    }

    component Item_: Rectangle {
        id: it
        property string text
        property bool checked: false
        signal clicked()
        Layout.fillWidth: true
        implicitWidth: row.implicitWidth + 20
        implicitHeight: 28
        radius: 6
        color: ia.containsMouse && it.enabled ? Theme.accent : "transparent"
        RowLayout {
            id: row
            anchors { fill: parent; leftMargin: 8; rightMargin: 10 }
            spacing: 6
            Text {
                text: it.checked ? "󰄬" : ""
                Layout.preferredWidth: 14
                color: Theme.fg; font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                text: it.text
                Layout.fillWidth: true
                Layout.maximumWidth: 320
                elide: Text.ElideRight
                color: it.enabled ? Theme.fg : Theme.fgDim
                font.family: Theme.font; font.pixelSize: 12
            }
        }
        MouseArea { id: ia; anchors.fill: parent; hoverEnabled: true; enabled: it.enabled; onClicked: it.clicked() }
    }
    component Sep: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 4; Layout.bottomMargin: 4
        Layout.leftMargin: 8; Layout.rightMargin: 8
        implicitHeight: 1
        color: "#26ffffff"
    }
}
