//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire

// Two bars per monitor: a floating pill dock at the bottom and a floating bar at the top.
ShellRoot {
    id: root
    // Icons are loaded once at start, so when KDE's icon theme changes,
    // restart the taskbar (it runs as the sb-taskbar systemd service).
    FileView {
        id: kdeglobals
        property string theme: ""
        path: Quickshell.env("HOME") + "/.config/kdeglobals"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = text().match(/\[Icons\][^\[]*?^Theme=(.*)$/m)
            const t = m ? m[1].trim() : ""
            if (theme !== "" && t !== theme)
                Quickshell.execDetached(["systemctl", "--user", "restart", "sb-taskbar.service"])
            theme = t
        }
    }

    // ---------- touchpad: four-finger tap, left-edge media control ----------
    // Switchboard group "Touchpad":
    //   "Four-finger tap: play / pause"         -> touchpad-taps.py (just reads the touchpad)
    //   "Left edge: tap play / pause, slide volume" -> touchpad-edge.py (takes the touchpad and
    //      passes everything except left-edge touches on through a virtual copy; also does the
    //      four-finger tap then, since nothing else can read a taken touchpad)
    readonly property bool tap4On: Modules.ids("Touchpad").includes("tap4playpause")
    readonly property bool edgeOn: Modules.ids("Touchpad").includes("edgemedia")
    readonly property var touchpadCmd: edgeOn
        ? ["python3", Qt.resolvedUrl("touchpad-edge.py").toString().replace("file://", "")].concat(tap4On ? ["--tap4"] : [])
        : ["python3", Qt.resolvedUrl("touchpad-taps.py").toString().replace("file://", "")]
    readonly property bool touchpadWanted: tap4On || edgeOn
    onTouchpadCmdChanged: { taps.running = false; tapsRestart.restart() }
    onTouchpadWantedChanged: { taps.running = false; tapsRestart.restart() }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    function changeVolume(delta) {
        const a = Pipewire.defaultAudioSink?.audio
        if (!a) return
        if (a.muted && delta > 0) a.muted = false
        a.volume = Math.max(0, Math.min(1, a.volume + delta))
        // Plasma's own volume pop-up, so you can see the level while sliding
        Quickshell.execDetached(["qdbus6", "org.kde.plasmashell", "/org/kde/osdService",
                                 "org.kde.osdService.volumeChanged", String(Math.round(a.volume * 100))])
    }

    Process {
        id: taps
        command: root.touchpadCmd
        running: root.touchpadWanted
        stdout: SplitParser {
            onRead: line => {
                const l = line.trim()
                if (l === "tap4" || l === "playpause") { if (NowPlaying.player) NowPlaying.player.togglePlaying() }
                else if (l.startsWith("vol ")) root.changeVolume(parseFloat(l.slice(4)))
            }
        }
        onExited: code => { if (root.touchpadWanted) tapsRestart.restart() }
    }
    Timer { id: tapsRestart; interval: 1500; onTriggered: taps.running = root.touchpadWanted }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            // ---------- bottom dock (auto-hides, macOS style) ----------
            // Windows get the whole screen; the dock slides up over them when the
            // pointer touches the bottom edge, and slides away shortly after it leaves.
            PanelWindow {
                id: dockWin
                screen: perScreen.modelData
                anchors { bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore   // reserve no space
                WlrLayershell.namespace: "taskbar-dock"
                WlrLayershell.layer: WlrLayer.Top

                // Room for the dock, its gap to the edge, and icons/labels rising above it.
                implicitHeight: Theme.dockHeight + Theme.gap + Theme.dockOverflow
                color: "transparent"

                // Up while you're using it, or whenever the desktop itself is in view.
                readonly property bool reveal: edge.hovered || dock.hovered || Menus.open === "dock"
                                               || Windows.desktopVisible
                property bool shown: false
                onRevealChanged: if (reveal) { hideDelay.stop(); shown = true } else hideDelay.restart()
                Timer { id: hideDelay; interval: 450; onTriggered: dockWin.shown = false }

                // Only the dock (when up) and a thin strip at the screen edge take input.
                mask: Region {
                    item: edgeStrip
                    Region { item: dock }
                }
                BackgroundEffect.blurRegion: Region { item: dock; radius: dock.radius }   // frosted glass

                // Touching the bottom edge under the dock brings it up.
                Item {
                    id: edgeStrip
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(dock.width, 400)
                    height: 3
                    HoverHandler { id: edge }
                }

                Dock {
                    id: dock
                    shown: dockWin.shown
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Shown: Theme.gap above the edge. Hidden: just below the screen.
                    y: dockWin.shown ? dockWin.height - Theme.gap - Theme.dockHeight : dockWin.height + 4
                    Behavior on y { NumberAnimation { duration: dockWin.shown ? 220 : 260; easing.type: dockWin.shown ? Easing.OutCubic : Easing.InCubic } }
                }
            }

            // ---------- desktop lyrics widget (switch in Switchboard; first screen only) ----------
            LazyLoader {
                active: Modules.ids("Desktop").includes("lyricswidget") && perScreen.modelData === Quickshell.screens[0]
                LyricsWidget { screen: perScreen.modelData }
            }

            // ---------- top bar ----------
            PanelWindow {
                id: topWin
                screen: perScreen.modelData
                anchors { top: true; left: true; right: true }

                exclusionMode: ExclusionMode.Normal
                exclusiveZone: Theme.barHeight   // windows start right below the bar
                WlrLayershell.namespace: "taskbar-top"
                WlrLayershell.layer: WlrLayer.Top

                implicitHeight: Theme.barHeight
                color: "transparent"
                mask: Region { item: topBar }
                // Blur behind the bar. (Glass's "edge lighting" for docks is turned off
                // in kwinrc so the full-width bar gets no white rim.) The media card has
                // its own window below, so opening it never changes this blur region.
                BackgroundEffect.blurRegion: Region { item: topBar }

                TopBar {
                    id: topBar
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                }
            }

            // ---------- media card that drops down from the top bar ----------
            PanelWindow {
                screen: perScreen.modelData
                anchors { top: true; left: true; right: true }

                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "taskbar-card"
                WlrLayershell.layer: WlrLayer.Top

                // Tall enough for the card; only the open card takes clicks / gets blur.
                implicitHeight: Theme.barHeight + Theme.cardGap + Theme.cardHeight
                color: "transparent"
                mask: Region { item: cardMask }
                // The glass follows the card's own fade/zoom: it only appears once the card is almost
                // fully in (else the glass frame shows up before the content) and goes as soon as it closes.
                BackgroundEffect.blurRegion: Region { item: cardBlur; radius: 28 * card.scale }

                MediaCard {
                    id: card
                    hoverOpen: topBar.mediaHovered || hovered
                    desktopOpen: Windows.desktopVisible && NowPlaying.player !== null && Modules.ids("Desktop").includes("desktopmedia")   // stays open on the desktop (Switchboard option)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Theme.barHeight + Theme.cardGap
                }

                Item {
                    id: cardBlur
                    readonly property bool on: card.shown && card.reveal > 0.92
                    width: on ? card.width * card.scale : 0
                    height: on ? card.height * card.scale : 0
                    x: card.x + (card.width - width) / 2      // the card zooms from its top centre
                    y: card.y + card.dropY
                }

                // Click area for the card: zero-sized while it's closed.
                Item {
                    id: cardMask
                    x: card.x; y: card.y
                    width: card.shown ? card.width : 0
                    height: card.shown ? card.height : 0
                }
            }

            // ---------- Control Center layer ----------
            // Full-screen and always mapped, so opening is instant. Closed: takes no
            // input at all. Open: catches clicks outside the panel (closing it) and
            // the keyboard (Esc, Wi-Fi passwords); the top bar is cut out so its
            // icons still work.
            PanelWindow {
                id: menuLayer
                readonly property bool active: Menus.open !== ""
                screen: perScreen.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "taskbar-menus"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                color: "transparent"

                property Region openMask: Region {
                    item: catcher
                    Region { item: barHole; intersection: Intersection.Subtract }
                }
                property Region closedMask: Region {}
                mask: active ? openMask : closedMask
                BackgroundEffect.blurRegion: Region {
                    item: ccBlur; radius: 24
                    Region { item: dockMenuBlur; radius: 12 }
                }

                FocusScope {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: Menus.open === "control" && Menus.page !== "main" ? Menus.page = "main" : Menus.close()

                    MouseArea {
                        id: catcher
                        anchors.fill: parent
                        onClicked: Menus.close()
                    }
                    Item {
                        id: barHole
                        x: 0; y: 0
                        width: parent.width
                        height: Theme.barHeight
                    }

                    ControlCenter { id: cc; focus: true }
                    // Blur area for the Control Center: zero-sized while it's closed.
                    Item {
                        id: ccBlur
                        x: cc.x; y: cc.y
                        width: cc.visible ? cc.width : 0
                        height: cc.visible ? cc.height : 0
                    }

                    DockMenu { id: dockMenu }
                    Item {
                        id: dockMenuBlur
                        x: dockMenu.x; y: dockMenu.y
                        width: dockMenu.visible ? dockMenu.width : 0
                        height: dockMenu.visible ? dockMenu.height : 0
                    }
                }
            }
        }
    }
}
