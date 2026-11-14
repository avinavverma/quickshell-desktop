pragma Singleton
import QtQuick
import Quickshell

// Which popup is open: the Control Center, or a dock icon's right-click menu.
Singleton {
    id: root
    property string open: ""      // "", "control" or "dock"
    property string page: "main"  // Control Center page: "main", "wifi" or "bluetooth"
    property real anchorX: 0      // Control Center: screen x of the chip's centre

    // dock menu
    property var dockEntry: null  // the dock item it's for
    property real dockX: 0        // screen x of the icon's centre
    property real dockY: 0        // screen y of the dock's top edge

    // chip: the item it hangs from (its centre is used).
    function toggle(name, chip, startPage) {
        if (open === name) { open = ""; return }
        if (chip) {
            const p = chip.mapToItem(null, chip.width / 2, 0)
            anchorX = p.x   // the top-bar window spans the screen from its left edge
        }
        page = startPage ?? "main"
        open = name
    }
    function openDock(entry, x, y) {
        dockEntry = entry; dockX = x; dockY = y
        open = "dock"
    }
    function close() { open = "" }
}
