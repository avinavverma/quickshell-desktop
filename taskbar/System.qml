pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screen brightness, Night Light and Do Not Disturb for the Control Center.
// State is refreshed while the Control Center is open.
Singleton {
    id: root
    property real brightness: 1      // 0..1
    property bool nightLight: false
    property bool dnd: false

    readonly property string pm: "org.kde.Solid.PowerManagement"
    readonly property string bc: "/org/kde/Solid/PowerManagement/Actions/BrightnessControl"

    function setBrightness(v) {
        brightness = Math.max(0.01, Math.min(1, v))
        if (!setter.running) setter.running = true
        else setter.pending = true
    }
    function toggleNightLight() {
        nightLight = !nightLight
        // nightlight.sh writes the settings *with a change notification* - KWin's
        // `reconfigure` does not reload Night Light, so the old way only changed the file.
        Quickshell.execDetached([Qt.resolvedUrl("nightlight.sh").toString().replace("file://", ""), nightLight ? "on" : "off"])
    }
    function toggleDnd() {
        dnd = !dnd
        Windows.setDnd(dnd)   // held by windows.py: the inhibit lasts as long as its connection
    }

    // Apply brightness; while dragging, coalesce to one call at a time.
    Process {
        id: setter
        property bool pending: false
        command: ["qdbus6", root.pm, root.bc, "setBrightnessSilent", String(Math.round(root.brightness * 10000))]
        onExited: if (pending) { pending = false; running = true }
    }

    // Read current state: "brightness max nightLightEnabled"
    Process {
        id: reader
        command: ["sh", "-c", `echo $(qdbus6 ${root.pm} ${root.bc} brightness) $(qdbus6 ${root.pm} ${root.bc} brightnessMax) $(qdbus6 org.kde.KWin.NightLight /org/kde/KWin/NightLight org.kde.KWin.NightLight.enabled)`]
        stdout: StdioCollector {
            onStreamFinished: {
                const [cur, max, night] = text.trim().split(" ")
                if (!setter.running && +max > 0) root.brightness = +cur / +max
                root.nightLight = night === "true"
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: Menus.open !== ""
        onTriggered: if (!reader.running) reader.running = true
    }
}
