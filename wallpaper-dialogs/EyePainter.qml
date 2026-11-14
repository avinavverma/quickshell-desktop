// Paintbrush for the eye mask: paint where the wallpaper's eye should take the cover-art
// colour. The mask is saved to eye-mask.png (same size as the eye patch; alpha = amount).
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: win

    property url src
    property rect patch                 // eye patch in image pixels
    property url maskUrl                // existing mask (may not exist yet)
    property string savePath            // local path to write the PNG to
    property var initialCircle: [0.5, 0.45, 0.30]   // fallback mask: cx, cy (0..1 of patch), r (of patch height)
    signal saved()
    signal cancelled()

    WlrLayershell.namespace: "wallpaper-dialogs-eyepaint"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#101014"

    property real brush: 28             // radius, image pixels
    property bool erasing: false
    property bool maskOnly: false
    property real mx: -100
    property real my: -100
    property string note: ""

    readonly property real z: Math.min((width - 80) / patch.width, (height - 150) / patch.height)

    // History: every stroke / clear / reset is an operation; undo pops one and the canvas is
    // redrawn from the saved mask plus the remaining operations.
    property int nUndo: 0
    property int nRedo: 0
    function touch() { nUndo = cv.ops.length; nRedo = cv.redoOps.length }
    function beginOp(op) { cv.ops.push(op); cv.redoOps = []; cv.cur = op.type === "stroke" ? op : null; cv.last = null; touch() }
    function undo() { if (!cv.ops.length) return; cv.redoOps.push(cv.ops.pop()); cv.full = true; cv.requestPaint(); touch() }
    function redo() { if (!cv.redoOps.length) return; cv.ops.push(cv.redoOps.pop()); cv.full = true; cv.requestPaint(); touch() }

    function stamp(ix, iy, erase) {
        cv.queue.push([ix, iy, erase, brush])
        if (cv.cur) cv.cur.pts.push([ix, iy])
        cv.requestPaint()
    }

    function strokeTo(sx, sy, erase) {       // screen coords -> stamps spaced along the move
        const ix = (sx - board.x) / z, iy = (sy - board.y) / z
        if (cv.last) {
            const dx = ix - cv.last[0], dy = iy - cv.last[1]
            const d = Math.hypot(dx, dy), step = Math.max(1, brush * 0.18)
            for (let t = step; t < d; t += step) stamp(cv.last[0] + dx * t / d, cv.last[1] + dy * t / d, erase)
        }
        stamp(ix, iy, erase)
        cv.last = [ix, iy]
    }

    function save() {
        cv.requestPaint()
        if (cv.save(win.savePath)) { note = ""; saved() } else note = "Could not save " + win.savePath
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: e => {
            if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Z) {
            if (e.modifiers & Qt.ShiftModifier) win.redo(); else win.undo()
        }
        else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Y) win.redo()
        else if (e.key === Qt.Key_Escape) win.cancelled()
            else if (e.key === Qt.Key_S || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.save()
            else if (e.key === Qt.Key_E) win.erasing = !win.erasing
            else if (e.key === Qt.Key_V) win.maskOnly = !win.maskOnly
            else if (e.key === Qt.Key_C) { win.beginOp({ type: "clear" }); cv.full = true; cv.requestPaint() }
            else if (e.key === Qt.Key_R) { win.beginOp({ type: "circle" }); cv.full = true; cv.requestPaint() }
        else if (e.key === Qt.Key_BracketRight) win.brush = Math.min(200, win.brush * 1.15)
            else if (e.key === Qt.Key_BracketLeft) win.brush = Math.max(3, win.brush / 1.15)
        }


        // The eye patch, enlarged.
        Item {
            id: board
            width: win.patch.width * win.z
            height: win.patch.height * win.z
            x: (parent.width - width) / 2
            y: 56

            Image {
                anchors.fill: parent
                visible: !win.maskOnly
                source: win.src
                sourceClipRect: Qt.rect(win.patch.x, win.patch.y, win.patch.width, win.patch.height)
                smooth: true
                mipmap: true
                cache: false
            }
            Rectangle { anchors.fill: parent; color: "black"; visible: win.maskOnly }

            // The mask being painted, drawn as a see-through magenta wash.
            Canvas {
                id: cv
                anchors.fill: parent
                renderTarget: Canvas.Image
                opacity: win.maskOnly ? 1 : 0.55
                property var queue: []
                property var last: null
                property bool init: true
                property var ops: []
                property var redoOps: []
                property var cur: null
                property bool full: false

                // The saved mask is loaded once as the starting point.
                Component.onCompleted: loadImage(win.maskUrl)
                onImageLoaded: requestPaint()
                Timer { running: cv.init; interval: 250; repeat: true; onTriggered: cv.requestPaint() }   // also covers a missing mask file

                function drawStamp(ctx, x, y, r, erase) {
                    const g = ctx.createRadialGradient(x, y, r * 0.55, x, y, r)
                    g.addColorStop(0, "rgba(0,229,255,1)")
                    g.addColorStop(1, "rgba(0,229,255,0)")
                    ctx.globalCompositeOperation = erase ? "destination-out" : "source-over"
                    ctx.fillStyle = g
                    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill()
                }
                function drawBase(ctx, W, H) {
                    ctx.globalCompositeOperation = "source-over"
                    ctx.clearRect(0, 0, W, H)
                    if (isImageLoaded(win.maskUrl)) {
                        ctx.drawImage(win.maskUrl, 0, 0, W, H)
                        ctx.globalCompositeOperation = "source-in"       // show it in the wash colour
                        ctx.fillStyle = "#00e5ff"; ctx.fillRect(0, 0, W, H)
                        ctx.globalCompositeOperation = "source-over"
                    } else drawDisc(ctx, W, H)
                }
                function drawDisc(ctx, W, H) {
                    const c = win.initialCircle
                    ctx.globalCompositeOperation = "source-over"
                    ctx.fillStyle = "#00e5ff"
                    ctx.beginPath(); ctx.arc(c[0] * W, c[1] * H, c[2] * H, 0, Math.PI * 2); ctx.fill()
                }

                onPaint: {
                    const ctx = getContext("2d")
                    const W = width, H = height, z = win.z
                    if (init) {
                        if (!(isImageLoaded(win.maskUrl) || isImageError(win.maskUrl))) return
                        init = false
                        drawBase(ctx, W, H)
                    }
                    if (full) {                       // undo / redo / clear: rebuild from the start
                        full = false
                        drawBase(ctx, W, H)
                        for (const op of ops) {
                            if (op.type === "clear") ctx.clearRect(0, 0, W, H)
                            else if (op.type === "circle") { ctx.clearRect(0, 0, W, H); drawDisc(ctx, W, H) }
                            else for (const p of op.pts) drawStamp(ctx, p[0] * z, p[1] * z, op.r * z, op.erase)
                        }
                        queue = []
                        return
                    }
                    for (const q of queue) drawStamp(ctx, q[0] * z, q[1] * z, q[3] * z, q[2])
                    queue = []
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.BlankCursor
            onPositionChanged: m => {
                win.mx = m.x; win.my = m.y
                if (pressedButtons & Qt.LeftButton) win.strokeTo(m.x, m.y, win.erasing)
                else if (pressedButtons & Qt.RightButton) win.strokeTo(m.x, m.y, true)
            }
            onPressed: m => {
                const er = m.button === Qt.RightButton || win.erasing
                win.beginOp({ type: "stroke", erase: er, r: win.brush, pts: [] })
                win.strokeTo(m.x, m.y, er)
            }
            onReleased: { cv.last = null; cv.cur = null }
            onWheel: w => { win.brush = Math.max(3, Math.min(200, win.brush * (w.angleDelta.y > 0 ? 1.12 : 1 / 1.12))) }
        }

        // Brush outline
        Rectangle {
            x: win.mx - width / 2; y: win.my - height / 2
            width: win.brush * 2 * win.z; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: win.erasing ? "#ffd400" : "white"
            Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 2; color: parent.border.color }
        }

        // Toolbar / help
        Rectangle {
            x: (parent.width - width) / 2; y: parent.height - height - 22
            width: help.implicitWidth + 32; height: help.implicitHeight + 20
            radius: 12; color: "#e01a1a22"; border.color: "#40ffffff"
            Text {
                id: help
                anchors.centerIn: parent
                color: "white"; font.pixelSize: 14; lineHeight: 1.4
                horizontalAlignment: Text.AlignHCenter
                text: "<b>Paint</b> where the eye should take the colour · <b>left drag</b> paint · <b>right drag</b> / <b>E</b> erase · <b>wheel</b> or <b>[ ]</b> brush size (" + Math.round(win.brush) + " px)<br>"
                    + "<b>Ctrl+Z</b> undo (" + win.nUndo + ") · <b>Ctrl+Shift+Z</b> / <b>Ctrl+Y</b> redo (" + win.nRedo + ")<br>"
                    + "<b>V</b> mask only · <b>C</b> clear · <b>R</b> reset to a circle · <b>S</b> / Enter save &amp; exit · <b>Esc</b> exit without saving"
                    + (win.note ? "<br><font color='#ff8080'>" + win.note + "</font>" : "")
            }
        }
        Text {
            x: (parent.width - width) / 2; y: 18
            color: win.erasing ? "#ffd400" : "#00e5ff"; font.pixelSize: 18; font.bold: true
            text: win.erasing ? "ERASER" : "BRUSH"
        }
    }

}
