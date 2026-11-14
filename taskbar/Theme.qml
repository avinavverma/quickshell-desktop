pragma Singleton
import QtQuick
import Quickshell

// All the look-and-feel knobs in one place.
Singleton {
    // Glass: a light, see-through tint (KWin blurs what's behind) with a fine
    // bright edge - the highlight is most of what reads as "glass".
    readonly property color bg: "#66202027"
    readonly property color border: "#3dffffff"
    readonly property color bgSolid: "#e01e1e24"   // for small popups/labels that must stay readable
    readonly property color barTint: "#40000000"   // top bar: just enough to keep text readable
    readonly property color fg: "#f2f2f5"
    readonly property color fgDim: "#99a0a0aa"
    readonly property color accent: NowPlaying.accent   // follows the cover art; red when nothing plays
    readonly property color divider: "#33ffffff"

    // Text uses Inter (the open, SF-Pro-like font); icon glyphs come from the
    // Nerd Font, which Qt falls back to automatically for characters Inter lacks.
    readonly property string font: "Inter"
    readonly property string iconFont: "FantasqueSansM Nerd Font Propo"
    readonly property int fontSize: 13

    readonly property int gap: 10            // space between bar and screen edge
    readonly property int barHeight: 36      // top bar (flush with the top edge)
    readonly property int dockHeight: 64     // bottom dock
    readonly property int dockSlot: 54       // width/height of one app slot in the dock
    readonly property int dockIcon: 48       // app icon size at rest
    readonly property real dockMagnify: 1.0  // hover zoom; 1 = off (macOS default). Try 1.75 for magnification
    readonly property int dockOverflow: 90   // room above the dock for magnified icons + name bubble
    readonly property int barPad: 16         // inner padding at the bar's ends
    readonly property int moduleSpacing: 14

    readonly property int cardWidth: 480     // expanded media card
    readonly property int cardHeight: 156
    readonly property int cardGap: 8         // space between bar and card

    readonly property int anim: 260
}
