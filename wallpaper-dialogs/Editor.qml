// Outline editor: a full-screen overlay showing the wallpaper with every dialog outline
// drawn on it. Drag corners, add/remove points, draw new outlines. Nothing is written
// until you press S / Enter.
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: win

    property var polys: []          // working copy: [[ [x,y], ... ], ...] in image pixels
    property var names: []
    property url src
    property real iw: 3840
    property real ih: 2160
    signal saved(var polys, var names)
    signal cancelled()

    WlrLayershell.namespace: "wallpaper-dialogs-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "black"

    readonly property real k: Math.max(width / iw, height / ih)
    readonly property real ox: (width - iw * k) / 2
    readonly property real oy: (height - ih * k) / 2

    // interaction state
    property var drawing: null      // array of points while drawing a new outline
    property var hover: ({ kind: "", pi: -1, vi: -1 })
    property var drag: null
    property real mx: 0
    property real my: 0
    property bool dirty: false

    function sx(p) { return ox + p[0] * k }
    function sy(p) { return oy + p[1] * k }

    function segDist(px, py, ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay
        const l2 = dx * dx + dy * dy
        const t = l2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
        const cx = ax + t * dx, cy = ay + t * dy
        return { d: Math.hypot(px - cx, py - cy), t: t, x: cx, y: cy }
    }

    function inPoly(poly, px, py) {
        let c = false
        for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
            const xi = sx(poly[i]), yi = sy(poly[i]), xj = sx(poly[j]), yj = sy(poly[j])
            if ((yi > py) !== (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) c = !c
        }
        return c
    }

    // What is under the pointer: a vertex, an edge, or the inside of an outline.
    function pick(px, py) {
        for (let pi = polys.length - 1; pi >= 0; pi--)
            for (let vi = 0; vi < polys[pi].length; vi++)
                if (Math.hypot(px - sx(polys[pi][vi]), py - sy(polys[pi][vi])) <= 11)
                    return { kind: "v", pi: pi, vi: vi }
        for (let pi = polys.length - 1; pi >= 0; pi--) {
            const P = polys[pi]
            for (let vi = 0; vi < P.length; vi++) {
                const a = P[vi], b = P[(vi + 1) % P.length]
                const s = segDist(px, py, sx(a), sy(a), sx(b), sy(b))
                if (s.d <= 7) return { kind: "e", pi: pi, vi: vi, x: s.x, y: s.y }
            }
        }
        for (let pi = polys.length - 1; pi >= 0; pi--)
            if (inPoly(polys[pi], px, py)) return { kind: "p", pi: pi, vi: -1 }
        return { kind: "", pi: -1, vi: -1 }
    }

    function finishDrawing() {
        if (drawing && drawing.length >= 3) {
            polys.push(drawing)
            names.push("dialog-" + (polys.length))
            dirty = true
        }
        drawing = null
    }

    function nudge(dx, dy) {
        const h = hover
        if (h.pi < 0) return
        if (h.kind === "v") { polys[h.pi][h.vi][0] += dx; polys[h.pi][h.vi][1] += dy }
        else for (const p of polys[h.pi]) { p[0] += dx; p[1] += dy }
        dirty = true
    }

    function move(from, to) {
        if (from < 0 || to < 0 || to >= polys.length) return
        polys.splice(to, 0, polys.splice(from, 1)[0])
        names.splice(to, 0, names.splice(from, 1)[0])
        hover = { kind: "p", pi: to, vi: -1 }
        dirty = true
    }

    Item {
        anchors.fill: parent
        focus: true

        Image {
            anchors.fill: parent
            source: win.src
            sourceSize: Qt.size(win.width, win.height)
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
        }

        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.lineJoin = "round"
                const P = win.polys
                for (let pi = 0; pi < P.length; pi++) {
                    const poly = P[pi]
                    const hot = win.hover.pi === pi
                    ctx.beginPath()
                    for (let i = 0; i < poly.length; i++) {
                        if (i === 0) ctx.moveTo(win.sx(poly[i]), win.sy(poly[i]))
                        else ctx.lineTo(win.sx(poly[i]), win.sy(poly[i]))
                    }
                    ctx.closePath()
                    ctx.fillStyle = hot ? "rgba(0,255,220,0.22)" : "rgba(0,255,220,0.08)"
                    ctx.fill()
                    ctx.lineWidth = 4; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.stroke()
                    ctx.lineWidth = 2; ctx.strokeStyle = hot ? "#fff200" : "#00ffd0"; ctx.stroke()
                    for (let vi = 0; vi < poly.length; vi++) {
                        const hv = win.hover.kind === "v" && hot && win.hover.vi === vi
                        const r = hv ? 7 : 5
                        ctx.fillStyle = hv ? "#fff200" : "white"
                        ctx.strokeStyle = "black"; ctx.lineWidth = 1.5
                        ctx.beginPath(); ctx.rect(win.sx(poly[vi]) - r, win.sy(poly[vi]) - r, r * 2, r * 2)
                        ctx.fill(); ctx.stroke()
                    }
                    ctx.font = "bold 13px sans-serif"
                    ctx.fillStyle = "black"; ctx.fillText((pi + 1) + "  " + win.names[pi], win.sx(poly[0]) + 9, win.sy(poly[0]) + 21)
                    ctx.fillStyle = "#fff"; ctx.fillText((pi + 1) + "  " + win.names[pi], win.sx(poly[0]) + 8, win.sy(poly[0]) + 20)
                }
                if (win.hover.kind === "e") {      // where a new point would go
                    ctx.fillStyle = "#fff200"; ctx.strokeStyle = "black"; ctx.lineWidth = 1.5
                    ctx.beginPath(); ctx.arc(win.hover.x, win.hover.y, 5, 0, Math.PI * 2); ctx.fill(); ctx.stroke()
                }
                const D = win.drawing
                if (D) {
                    ctx.beginPath()
                    for (let i = 0; i < D.length; i++) {
                        if (i === 0) ctx.moveTo(win.sx(D[i]), win.sy(D[i])); else ctx.lineTo(win.sx(D[i]), win.sy(D[i]))
                    }
                    ctx.lineTo(win.mx, win.my)
                    ctx.lineWidth = 4; ctx.strokeStyle = "rgba(0,0,0,0.7)"; ctx.stroke()
                    ctx.lineWidth = 2; ctx.strokeStyle = "#ff4fd8"; ctx.stroke()
                    for (let i = 0; i < D.length; i++) {
                        const r = i === 0 ? 7 : 5
                        ctx.fillStyle = i === 0 ? "#ff4fd8" : "white"; ctx.strokeStyle = "black"; ctx.lineWidth = 1.5
                        ctx.beginPath(); ctx.rect(win.sx(D[i]) - r, win.sy(D[i]) - r, r * 2, r * 2); ctx.fill(); ctx.stroke()
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: win.drawing ? Qt.CrossCursor
                       : win.drag ? Qt.ClosedHandCursor
                       : win.hover.kind === "v" ? Qt.PointingHandCursor
                       : win.hover.kind === "e" ? Qt.CrossCursor
                       : win.hover.kind === "p" ? Qt.OpenHandCursor : Qt.ArrowCursor

            onPositionChanged: m => {
                win.mx = m.x; win.my = m.y
                const d = win.drag
                if (d) {
                    const ix = (m.x - win.ox) / win.k, iy = (m.y - win.oy) / win.k
                    if (d.type === "v") {
                        const p = win.polys[d.pi][d.vi]
                        p[0] = Math.round(ix); p[1] = Math.round(iy)
                    } else {
                        const dx = Math.round(ix - d.ix), dy = Math.round(iy - d.iy)
                        win.polys[d.pi].forEach((p, i) => { p[0] = d.orig[i][0] + dx; p[1] = d.orig[i][1] + dy })
                    }
                    win.dirty = true
                } else if (!win.drawing) {
                    win.hover = win.pick(m.x, m.y)
                }
                cv.requestPaint()
            }

            onPressed: m => {
                const ix = Math.round((m.x - win.ox) / win.k), iy = Math.round((m.y - win.oy) / win.k)
                if (win.drawing) {
                    const D = win.drawing
                    if (m.button === Qt.RightButton) { D.pop(); cv.requestPaint(); return }
                    if (D.length >= 3 && Math.hypot(m.x - win.sx(D[0]), m.y - win.sy(D[0])) <= 11) {
                        win.finishDrawing(); win.hover = win.pick(m.x, m.y)
                    } else D.push([ix, iy])
                    cv.requestPaint(); return
                }
                const h = win.pick(m.x, m.y)
                win.hover = h
                if (m.button === Qt.RightButton) {
                    if (h.kind === "v" && win.polys[h.pi].length > 3) { win.polys[h.pi].splice(h.vi, 1); win.dirty = true }
                    else if (h.kind === "p" || h.kind === "e") { win.polys.splice(h.pi, 1); win.names.splice(h.pi, 1); win.dirty = true }
                    win.hover = win.pick(m.x, m.y)
                } else if (h.kind === "v") {
                    win.drag = { type: "v", pi: h.pi, vi: h.vi }
                } else if (h.kind === "e") {
                    win.polys[h.pi].splice(h.vi + 1, 0, [ix, iy])
                    win.drag = { type: "v", pi: h.pi, vi: h.vi + 1 }
                    win.dirty = true
                } else if (h.kind === "p") {
                    win.drag = { type: "p", pi: h.pi, ix: (m.x - win.ox) / win.k, iy: (m.y - win.oy) / win.k,
                                 orig: win.polys[h.pi].map(p => [p[0], p[1]]) }
                }
                cv.requestPaint()
            }
            onReleased: { win.drag = null; cv.requestPaint() }
        }

        // Help
        Rectangle {
            x: 24; y: win.height - height - 24
            width: helpText.implicitWidth + 28; height: helpText.implicitHeight + 20
            radius: 12; color: "#d0101018"; border.color: "#40ffffff"
            Text {
                id: helpText
                anchors.centerIn: parent
                color: "white"; font.pixelSize: 13; lineHeight: 1.35
                text: win.drawing
                    ? "<b>Drawing</b>: click corners, click the pink first point (or Enter) to close · right-click: undo point · Esc: cancel"
                    : "<b>Drag</b> corner: move · drag edge: add a corner · drag inside: move all · right-click corner: remove · right-click inside: delete<br>"
                      + "<b>N</b> draw a new outline · <b>[ ]</b> send back / bring forward · <b>arrows</b> nudge (Shift = 10px) · <b>S / Enter</b> save &amp; exit · <b>Esc</b> exit without saving"
            }
        }

        Keys.onPressed: e => {
            const step = (e.modifiers & Qt.ShiftModifier) ? 10 : 1
            if (e.key === Qt.Key_Escape) {
                if (drawing) { drawing = null; cv.requestPaint() } else cancelled()
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (drawing) { finishDrawing(); cv.requestPaint() } else saved(polys, names)
            } else if (e.key === Qt.Key_S && !drawing) {
                saved(polys, names)
            } else if (e.key === Qt.Key_N) {
                drawing = []; hover = { kind: "", pi: -1, vi: -1 }; cv.requestPaint()
            } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                if (hover.pi >= 0) { polys.splice(hover.pi, 1); names.splice(hover.pi, 1); hover = { kind: "", pi: -1, vi: -1 }; cv.requestPaint() }
            } else if (e.key === Qt.Key_BracketRight) { move(hover.pi, hover.pi + 1); cv.requestPaint()
            } else if (e.key === Qt.Key_BracketLeft)  { move(hover.pi, hover.pi - 1); cv.requestPaint()
            } else if (e.key === Qt.Key_Left)  { nudge(-step, 0); cv.requestPaint()
            } else if (e.key === Qt.Key_Right) { nudge(step, 0);  cv.requestPaint()
            } else if (e.key === Qt.Key_Up)    { nudge(0, -step); cv.requestPaint()
            } else if (e.key === Qt.Key_Down)  { nudge(0, step);  cv.requestPaint() }
        }
    }
}
