pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Synced lyrics for the playing song (LRCLIB, via lyrics-fetch.sh), as one current line.
//   line      -> the line being sung now ("" when none / no lyrics / not playing)
// Needs a player that reports a real position (YouTube Music through the Firefox add-on does;
// Apple Music's web player reports 0, so no lyrics there).
Singleton {
    id: root

    readonly property var pp: NowPlaying.progressPlayer
    readonly property var song: NowPlaying.player
    readonly property bool playing: pp?.isPlaying ?? false

    // Look songs up by their FULL names ("Levitating (feat. DaBaby)" is a different version from
    // "Levitating"); only the display in the bar is shortened.
    readonly property string artist: (song?.trackArtist ?? "").replace(/\s*-\s*Topic$/i, "").trim()
    readonly property string title: (song?.trackTitle ?? "").trim()
    readonly property int duration: {
        const l = pp?.lengthSupported ? pp.length : 0
        return NowPlaying.lengthTrusted ? Math.round(l) : 0
    }
    readonly property string key: artist && title ? artist + "\u0001" + title : ""

    property var lines: []          // [{t: seconds, text}]
    property string loadedKey: ""

    // A song change updates title / artist / length / album one after another, so wait a moment for
    // them to settle (a lookup with the previous song's length found nothing and was remembered).
    // The cache entry also depends on the length, for the same reason.
    Timer { id: settle; interval: 700; onTriggered: root.startFetch() }
    function scheduleFetch() { lines = []; loadedKey = ""; fetcher.running = false; if (key) settle.restart() }
    function startFetch() {
        lines = []; loadedKey = ""
        fetcher.running = false
        if (!key) return
        fetcher.command = ["sh", Qt.resolvedUrl("lyrics-fetch.sh").toString().replace("file://", ""),
                           artist, title, NowPlaying.album, String(duration),
                           (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/taskbar-lyrics-v2/" + Qt.md5(key + "|" + duration) + ".lrc"]
        fetcher.forKey = key
        fetcher.tries = 1
        fetcher.running = true
    }
    onKeyChanged: scheduleFetch()
    onDurationChanged: if (key) scheduleFetch()
    Component.onCompleted: if (key) scheduleFetch()   // a song is already playing when the shell (re)loads

    // A source timed out or errored (exit code 3, nothing cached): try again a few times.
    Timer {
        id: retry
        interval: 15000
        onTriggered: if (fetcher.forKey === root.key && root.lines.length === 0) fetcher.running = true
    }
    Process {
        id: fetcher
        property string forKey
        property int tries: 1
        onExited: code => {
            if (code === 3 && forKey === root.key && tries < 4) { tries++; retry.restart() }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (fetcher.forKey !== root.key) return           // song changed meanwhile
                const out = []
                for (const raw of text.split("\n")) {
                    const m = raw.match(/^((?:\[\d+:\d+(?:[.:]\d+)?\])+)\s*(.*)$/)
                    if (!m) continue
                    for (const ts of m[1].match(/\[[^\]]+\]/g)) {
                        const p = ts.slice(1, -1).split(/[:.]/)
                        const frac = p[2] ? parseFloat("0." + p[2]) : 0
                        out.push({ t: parseInt(p[0]) * 60 + parseInt(p[1]) + frac, text: m[2].trim() })
                    }
                }
                out.sort((a, b) => a.t - b.t)
                root.lines = out
                root.loadedKey = fetcher.forKey
            }
        }
    }

    // Poll the position 10x/s while lyrics are showing (MPRIS doesn't push it).
    readonly property real pos: (pp?.position ?? 0) + leadSeconds
    readonly property real leadSeconds: 0     // lines are shown exactly at their timestamp
    Timer {
        running: root.lines.length > 0 && root.playing
        interval: 100; repeat: true
        onTriggered: root.pp.positionChanged()
    }

    // Index of the line being sung (even when paused, for the desktop widget); -1 before the first line.
    readonly property int lineIndex: {
        if (lines.length === 0) return -1
        const t = pos
        let lo = 0, hi = lines.length - 1, idx = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lines[mid].t <= t) { idx = mid; lo = mid + 1 } else hi = mid - 1
        }
        return idx
    }
    readonly property bool loading: fetcher.running
    readonly property string line: {
        if (!playing || lineIndex < 0) return ""
        const l = lines[lineIndex]
        return l.text === "" ? "♪" : l.text
    }
}

