pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which modules are on, where they go, and in what order. Read live from
// modules.json, which Switchboard edits. Each entry:
//   { id, name, enabled, group: "Dock" | "Top bar", section: "left" | "center" | "right" }
Singleton {
    id: root
    property var list: []

    // Enabled module ids for one bar (and, for the top bar, one section), in file order.
    function ids(group, section) {
        return list.filter(m => m.enabled && m.group === group
                              && (section === undefined || (m.section ?? "center") === section))
                   .map(m => m.id)
    }

    FileView {
        path: Qt.resolvedUrl("modules.json").toString().replace("file://", "")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.list = JSON.parse(text()) }
            catch (e) { console.warn("modules.json is not valid JSON:", e) }
        }
    }
}
