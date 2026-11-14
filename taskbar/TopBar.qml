import QtQuick

// Full-width menu bar flush with the top edge: left / center / right sections.
Rectangle {
    id: top
    readonly property bool mediaHovered: left.mediaHovered || center.mediaHovered || right.mediaHovered

    height: Theme.barHeight
    color: Theme.barTint   // transparent-ish, macOS 26 style (no glass, no outline)

    ModuleRow {
        id: left
        anchors { left: parent.left; leftMargin: Theme.barPad; verticalCenter: parent.verticalCenter }
        ids: Modules.ids("Top bar", "left")
        dividers: false; hoverPills: true
    }
    ModuleRow {
        id: center
        anchors.centerIn: parent
        ids: Modules.ids("Top bar", "center")
        dividers: false
    }
    ModuleRow {
        id: right
        anchors { right: parent.right; rightMargin: Theme.barPad; verticalCenter: parent.verticalCenter }
        ids: Modules.ids("Top bar", "right")
        dividers: false; hoverPills: true
        spacing: 20
    }
}
