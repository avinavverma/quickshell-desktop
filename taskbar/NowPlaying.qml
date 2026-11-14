pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Io

// What's playing, for the media chip, card and Control Center.
//
// Browsers can show up twice (their own MPRIS player + KDE's Plasma Browser
// Integration add-on), and which one has the real song info varies. So:
//   player         -> song info + play/pause/next: the playing player that
//                     actually has an artist (not just the page title)
//   progressPlayer -> position/length/seek: the same player if it reports them,
//                     otherwise another playing player that does
//   lengthTrusted  -> false for sites whose reported length is wrong
//                     (Apple Music web reports ~2× the song length)
Singleton {
    id: root
    readonly property var players: Mpris.players.values

    function isAddon(p) { return (p?.dbusName ?? "").indexOf("plasma-browser-integration") >= 0 }
    function hasProgress(p) { return !!p && p.lengthSupported && p.positionSupported && p.length > 0 }

    function hasInfo(p) { return !!p && (p.trackArtist ?? "") !== "" && (p.trackTitle ?? "") !== "" }

    // Display names: just the main title (nothing after a parenthesis / bracket, "feat." / "ft.",
    // or a " - " suffix like "- Remastered") and just the first, main artist.
    function mainTitle(t) {
        const s = (t ?? "") + ""
        const m = s.replace(/\s*(?:[\(\[\{]|\bfeat\b\.?|\bft\b\.?|\bfeaturing\b|\s[-\u2013\u2014|]\s|\s\/\/\s).*$/i, "").trim()
        return m || s.trim()
    }
    function mainArtist(a) {
        const s = (a ?? "") + ""
        const m = s.replace(/\s*-\s*Topic$/i, "").replace(/VEVO$/i, "")
                   .split(/\s*(?:,|;|\band\b|\bwith\b|\bfeat\b\.?|\bft\b\.?|\bfeaturing\b|\sx\s)\s*/i)[0].trim()
        return m || s.trim()
    }

    readonly property MprisPlayer player:
        players.find(p => p.isPlaying && hasInfo(p))
        ?? players.find(p => p.isPlaying)
        ?? players.find(p => hasInfo(p))
        ?? players[0] ?? null

    // Bring up wherever the song is playing: the browser tab / window or the player app.
    // The browser's own MPRIS player and the Plasma Browser Integration add-on describe the same
    // song; raising both switches to the tab (add-on) and the window (browser).
    function openPlayer() {
        if (!player) return
        const url = (player.metadata?.["xesam:url"] ?? "") + ""
        const related = players.filter(p => p === player
            || (url !== "" && ((p.metadata?.["xesam:url"] ?? "") + "") === url)
            || (p.isPlaying && player.isPlaying && p.trackTitle === player.trackTitle))
        related.sort((a, b) => (isAddon(b) ? 1 : 0) - (isAddon(a) ? 1 : 0))     // add-on first (tab), browser last (window)
        for (const p of related) if (p.canRaise) p.raise()          // browsers: switches to the tab
        // Raise() can't bring back a minimised window (or focus on Wayland), so also focus the app's
        // window through KWin - the one whose title mentions the song if there are several.
        const entries = related.map(p => (p.desktopEntry ?? "").replace(/\.desktop$/, "")).filter(e => e !== "")
        const cands = Windows.list.filter(w => entries.some(e => w.app === e || w.app === e + ".desktop"))
        const w = cands.find(w => player.trackTitle && (w.title ?? "").indexOf(player.trackTitle) >= 0) ?? cands[0]
        if (w) Windows.focus(w.id)
    }

    // YouTube Music's page stops sending the album name when a song starts again by itself
    // (repeat / loop), so remember the last album seen for each title + artist.
    property var albumMemory: ({})
    readonly property string songKey: (player?.trackTitle ?? "") + "\u0001" + (player?.trackArtist ?? "")
    function rememberAlbum() {
        const a = player?.trackAlbum ?? ""
        if (a !== "" && songKey !== "\u0001" && albumMemory[songKey] !== a) {
            const m = Object.assign({}, albumMemory); m[songKey] = a; albumMemory = m
        }
    }
    Connections {
        target: root.player
        function onTrackAlbumChanged() { root.rememberAlbum() }
        function onTrackTitleChanged() { root.rememberAlbum() }
        function onTrackArtistChanged() { root.rememberAlbum() }
    }
    onPlayerChanged: rememberAlbum()
    readonly property string album: (player?.trackAlbum ?? "") !== "" ? player.trackAlbum : (albumMemory[songKey] ?? "")

    readonly property string title: mainTitle(player?.trackTitle)
    readonly property string artist: mainArtist(player?.trackArtist)

    readonly property MprisPlayer progressPlayer:
        hasProgress(player) ? player
        : (players.find(p => p.isPlaying && hasProgress(p)) ?? null)

    // Apple Music's web player reports a wrong (too long) length, so only the
    // elapsed time is meaningful there.
    readonly property bool lengthTrusted:
        ((progressPlayer?.metadata?.["xesam:url"] ?? "") + "").indexOf("music.apple.com") < 0

    // ---------- cover art ----------
    // The player's own art, or - for YouTube / YouTube Music, where the browser
    // add-on passes no artwork - the video's thumbnail from YouTube's image
    // server, cropped to the square cover in its centre.
    //   artUrl  -> where the art comes from (may be a web address)
    //   artFile -> local file to display / analyse (web art is downloaded, and
    //              YouTube thumbnails cropped, into $XDG_RUNTIME_DIR/taskbar-art)
    function youtubeId(p) {
        const url = (p?.metadata?.["xesam:url"] ?? "") + ""
        const m = url.match(/(?:youtube\.com\/watch\?(?:.*&)?v=|youtu\.be\/)([A-Za-z0-9_-]{11})/)
        return m ? m[1] : ""
    }
    // The add-on can keep handing out the PREVIOUS song's cover for a while after a new song starts.
    // A moment after each song change, a cover URL that is still the one from the previous song is
    // treated as stale (and the YouTube thumbnail is used) until the add-on sends a different one.
    property string settledArt: ""
    property string settledKey: ""
    property string staleUrl: ""
    readonly property bool artStale: staleUrl !== "" && (player?.trackArtUrl ?? "") === staleUrl
    Timer {
        id: artSettle
        interval: 1800
        onTriggered: {
            const art = root.player?.trackArtUrl ?? ""
            if (root.songKey !== root.settledKey && art !== "" && art === root.settledArt) root.staleUrl = art
            root.settledArt = art
            root.settledKey = root.songKey
            // Also: a cover file written long before this song started belongs to an earlier song.
            if (art.startsWith("file://")) { artAge.art = art; artAge.command = ["stat", "-c", "%Y", art.slice(7)]; artAge.running = true }
        }
    }
    Process {
        id: artAge
        property string art
        stdout: StdioCollector {
            onStreamFinished: {
                const written = parseInt(text)
                const started = Date.now() / 1000 - Math.max(0, (root.player?.position ?? 0))
                if (written > 0 && artAge.art === (root.player?.trackArtUrl ?? "") && written < started - 20) root.staleUrl = artAge.art
            }
        }
    }
    onSongKeyChanged: artSettle.restart()

    readonly property string ytId: {
        if (player?.trackArtUrl && !artStale) return ""
        if (!artStale) for (const p of players) if (p.isPlaying && p.trackTitle === player?.trackTitle && p.trackArtUrl) return ""
        for (const p of players) { const id = youtubeId(p); if (p.isPlaying && id) return id }
        return ""
    }
    readonly property string artUrl: {
        if (player?.trackArtUrl && !artStale) return player.trackArtUrl
        if (!artStale) for (const p of players) if (p.isPlaying && p.trackTitle === player?.trackTitle && p.trackArtUrl) return p.trackArtUrl
        return ytId ? `https://i.ytimg.com/vi/${ytId}/maxresdefault.jpg` : ""
    }

    property string artFile: ""
    readonly property string cacheDir: Quickshell.env("XDG_RUNTIME_DIR") + "/taskbar-art"
    onArtUrlChanged: {
        if (!artUrl) { artFile = ""; return }
        if (!artUrl.startsWith("http")) { artFile = artUrl; return }
        const dest = cacheDir + "/" + Qt.md5(artUrl) + (ytId ? "-square.jpg" : ".img")
        fetcher.dest = dest
        fetcher.command = ytId
            // YouTube: 16:9 maxres frame -> centre square; else the 4:3 hq frame
            // (16:9 picture letterboxed inside) -> centre square inside the bars.
            ? ["sh", "-c", 'mkdir -p "$1" && [ -s "$2" ] && exit 0; t="$2.tmp"; ' +
                           'if curl -fsSL --max-time 10 -o "$t" "https://i.ytimg.com/vi/$3/maxresdefault.jpg"; then c="crop=ih:ih"; ' +
                           'else curl -fsSL --max-time 10 -o "$t" "https://i.ytimg.com/vi/$3/hqdefault.jpg" || exit 1; c="crop=ih*3/4:ih*3/4"; fi; ' +
                           'ffmpeg -loglevel error -y -i "$t" -vf "$c" -q:v 2 "$2" && rm -f "$t"',
               "sh", cacheDir, dest, ytId]
            : ["sh", "-c", 'mkdir -p "$1" && { [ -s "$2" ] || curl -fsSL --max-time 10 -o "$2" "$3"; }',
               "sh", cacheDir, dest, artUrl]
        fetcher.running = true
    }
    Process {
        id: fetcher
        property string dest
        onExited: code => { if (code === 0) root.artFile = "file://" + dest }
    }

    // ---------- accent colour from the cover art ----------
    // The taskbar's accent follows the playing song's artwork; red when nothing plays.
    readonly property color defaultAccent: "#e5484d"
    ColorQuantizer {
        id: quantizer
        // ColorQuantizer only reads local files, so web art is cached first.
        source: root.artFile
        depth: 3            // up to 8 colours
        rescaleSize: 64     // analyse a small copy - fast
    }
    // Most vivid usable colour, nudged to a lightness that reads well on dark glass.
    function pickAccent(colors) {
        let best = null, bestScore = 0
        for (const c of colors ?? []) {
            const l = c.hslLightness, s = c.hslSaturation
            if (l < 0.12 || l > 0.92) continue          // near black / white
            const score = s * (1 - Math.abs(l - 0.5))   // saturated and mid-light
            if (score > bestScore) { bestScore = score; best = c }
        }
        if (!best || best.hslSaturation < 0.18) return null   // greyscale art
        return Qt.hsla(best.hslHue, Math.max(best.hslSaturation, 0.5),
                       Math.max(0.45, Math.min(0.62, best.hslLightness)), 1)
    }
    readonly property color targetAccent:
        (player?.isPlaying ?? false) ? (pickAccent(quantizer.colors) ?? defaultAccent) : defaultAccent
    property color accent: targetAccent
    Behavior on accent { ColorAnimation { duration: 600; easing.type: Easing.InOutQuad } }

    // Shared with other shell projects (e.g. wallpaper-dialogs recolours the wallpaper's eye):
    // $XDG_RUNTIME_DIR/taskbar-accent holds "#rrggbb" of the playing song's cover art, or
    // "none" when nothing plays.
    // For the eye there is no legibility restriction: a vivid cover gives its most vivid colour,
    // and a white / grey / black cover gives its overall average, so the eye can be white too.
    ColorQuantizer {
        id: avgQuantizer
        source: root.artFile
        depth: 0            // one box = the picture's average colour
        rescaleSize: 64
    }
    function pickEyeColor() {
        let best = null, bestScore = 0
        for (const c of quantizer.colors ?? []) {
            const l = c.hslLightness, sat = c.hslSaturation
            if (sat < 0.25 || l < 0.08 || l > 0.92) continue
            const score = sat * (1 - Math.abs(l - 0.5))
            if (score > bestScore) { bestScore = score; best = c }
        }
        return best ?? (avgQuantizer.colors?.length ? avgQuantizer.colors[0] : null)
    }
    readonly property string sharedAccent: {
        quantizer.colors; avgQuantizer.colors            // re-evaluate when the art changes
        const c = (player?.isPlaying ?? false) ? pickEyeColor() : null
        return c ? Qt.rgba(c.r, c.g, c.b, 1).toString().slice(0, 7) : "none"
    }
    FileView {
        id: sharedAccentFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp") + "/taskbar-accent"
        atomicWrites: true
        printErrors: false
    }
    onSharedAccentChanged: sharedAccentFile.setText(sharedAccent)
    Component.onCompleted: { sharedAccentFile.setText(sharedAccent); artSettle.restart() }

    // MPRIS doesn't push position updates; poll while playing (4×/s for a smooth bar).
    Timer {
        running: (root.player?.isPlaying ?? false) || (root.progressPlayer?.isPlaying ?? false)
        interval: 250; repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged()
            if (root.progressPlayer && root.progressPlayer !== root.player) root.progressPlayer.positionChanged()
        }
    }
}
