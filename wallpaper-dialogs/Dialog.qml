// One "Serious error occurred" box cut out of the wallpaper along its outline.
// At rest it is hidden (the flat wallpaper underneath shows the same pixels), so an
// idle desktop costs nothing. On hover it lifts, tilts toward the cursor and casts a
// shadow; on leave it springs back and hides again.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    required property var entry        // {name, poly: [[x,y],...]} in image pixels
    required property var holes        // outlines (image px) of dialogs in front of this one
    required property url source       // full-resolution wallpaper
    required property real k           // image px -> screen px
    required property real ox          // screen offset of the (cropped) image
    required property real oy
    property int order: 0
    property real clock: 0        // seconds, shared by all boxes (shell.qml)
    property bool floating: true
    property real floatAmount: 1.0
    // Re-hued patch (the eye), if it lies inside this box.
    property var tintRect: [0, 0, 0, 0]
    property color tintAccent: "#e5484d"
    property real tintAmount: 0
    property real tintSpread: 0.45
    property real tintVariety: 0.0
    property url tintMask
    property int tintMaskRev: 0

    // Feel
    readonly property real maxTilt: 8        // degrees
    readonly property real liftScale: 0.07   // 7% bigger when lifted

    // Bounding box of the outline, in image pixels.
    readonly property var bb: {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const p of entry.poly) {
            x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1])
            x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1])
        }
        x0 = Math.floor(x0); y0 = Math.floor(y0)
        return { x: x0, y: y0, w: Math.max(1, Math.ceil(x1) - x0), h: Math.max(1, Math.ceil(y1) - y0) }
    }

    x: ox + bb.x * k
    y: oy + bb.y * k
    width: bb.w * k
    height: bb.h * k

    // Pointer must be inside the outline, not just its bounding box.
    property bool inside: false
    readonly property bool hovered: inside
    property real nx: 0     // cursor across the box, -1 .. 1
    property real ny: 0

    function hit(mx, my) {
        const poly = entry.poly
        let c = false
        for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
            const xi = (poly[i][0] - bb.x) * k, yi = (poly[i][1] - bb.y) * k
            const xj = (poly[j][0] - bb.x) * k, yj = (poly[j][1] - bb.y) * k
            if ((yi > my) !== (yj > my) && mx < (xj - xi) * (my - yi) / (yj - yi) + xi) c = !c
        }
        return c
    }

    property real lift: hovered ? 1 : 0
    property real tiltX: hovered ? -ny * maxTilt : 0
    property real tiltY: hovered ? nx * maxTilt : 0
    property real shiftX: hovered ? nx : 0
    property real shiftY: hovered ? ny : 0
    Behavior on lift   { SpringAnimation { spring: 5;   damping: 0.38; epsilon: 0.001 } }
    Behavior on tiltX  { SpringAnimation { spring: 4.5; damping: 0.5;  epsilon: 0.01 } }
    Behavior on tiltY  { SpringAnimation { spring: 4.5; damping: 0.5;  epsilon: 0.01 } }
    Behavior on shiftX { SpringAnimation { spring: 4.5; damping: 0.5;  epsilon: 0.002 } }
    Behavior on shiftY { SpringAnimation { spring: 4.5; damping: 0.5;  epsilon: 0.002 } }

    readonly property bool active: floating || lift > 0.002 || Math.abs(tiltX) > 0.02 || Math.abs(tiltY) > 0.02
    z: hovered ? 1000 : active ? 500 + order : order

    // Input stays on the untransformed bounding box so tilting never changes what is hovered.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            root.inside = root.hit(mouse.x, mouse.y)
            root.nx = Math.max(-1, Math.min(1, mouse.x / width * 2 - 1))
            root.ny = Math.max(-1, Math.min(1, mouse.y / height * 2 - 1))
        }
        onExited: root.inside = false
    }

    // Idle drift: each box wanders on its own slow sine waves. The card is a touch larger
    // than the box so the flat wallpaper copy underneath never peeks out.
    readonly property real fa: floating ? floatAmount : 0
    readonly property real fx: fa * 3.0 * Math.sin(clock * 0.55 + order * 1.7)
    readonly property real fy: fa * 3.5 * Math.sin(clock * 0.43 + order * 2.3)
    readonly property real frx: fa * 1.2 * Math.sin(clock * 0.37 + order * 1.1)
    readonly property real fry: fa * 1.2 * Math.sin(clock * 0.31 + order * 1.9)
    readonly property real cs: 1 + (floating ? 0.025 + 0.004 * fa : 0) + liftScale * Math.max(0, lift)   // current scale
    readonly property real liftC: Math.max(0, Math.min(1, lift))
    readonly property real shadowAmt: floating ? 0.7 + 0.3 * liftC : liftC   // resting shadow, deeper on hover

    // Outline as a canvas path, reused for the mask and the shadow.
    function tracePath(ctx, poly) {
        ctx.beginPath()
        for (let i = 0; i < poly.length; i++) {
            const px = (poly[i][0] - bb.x) * k, py = (poly[i][1] - bb.y) * k
            if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
        }
        ctx.closePath()
    }

    // Outline minus the dialogs in front of it.
    Canvas {
        id: mask
        width: root.width
        height: root.height
        visible: false
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Immediate
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onEntryChanged() { mask.requestPaint() }
            function onHolesChanged() { mask.requestPaint() }
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = "white"
            root.tracePath(ctx, root.entry.poly)
            ctx.fill()
            ctx.globalCompositeOperation = "destination-out"
            for (const h of root.holes) { root.tracePath(ctx, h); ctx.fill() }
        }
    }

    // Soft shadow on the "desk": the same silhouette, blurred, drifting away from the cursor.
    MultiEffect {
        anchors.fill: parent
        visible: root.active
        source: mask
        colorization: 1
        colorizationColor: Qt.rgba(0, 0, 0, 1)
        blurEnabled: true
        blurMax: 64
        blur: 1
        opacity: 0.85 * root.shadowAmt
        x: -root.shiftX * 16 + root.fx * 0.6
        y: 18 + 26 * root.liftC + root.shiftY * 6 + root.fy * 0.6
        transform: Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.cs; yScale: root.cs }
    }

    Item {
        id: card
        anchors.fill: parent
        visible: root.active
        transform: [
            Rotation { origin.x: card.width / 2; origin.y: card.height / 2; axis { x: 1; y: 0; z: 0 } angle: root.tiltX + root.frx },
            Rotation { origin.x: card.width / 2; origin.y: card.height / 2; axis { x: 0; y: 1; z: 0 } angle: root.tiltY + root.fry },
            Scale { origin.x: card.width / 2; origin.y: card.height / 2; xScale: root.cs; yScale: root.cs },
            Translate { x: root.shiftX * 4 + root.fx; y: -6 * root.lift + root.fy + root.shiftY * 3 }
        ]

        Item {
            anchors.fill: parent
            layer.enabled: card.visible
            layer.smooth: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }

            Image {
                anchors.fill: parent
                source: root.source
                sourceClipRect: Qt.rect(root.bb.x, root.bb.y, root.bb.w, root.bb.h)
                smooth: true
                mipmap: true
                asynchronous: true
                cache: false
            }

            EyeTint {
                readonly property bool here: root.tintRect[2] > 0
                    && root.tintRect[0] >= root.bb.x && root.tintRect[1] >= root.bb.y
                    && root.tintRect[0] + root.tintRect[2] <= root.bb.x + root.bb.w
                    && root.tintRect[1] + root.tintRect[3] <= root.bb.y + root.bb.h
                visible: here && amount > 0.002
                x: (root.tintRect[0] - root.bb.x) * root.k
                y: (root.tintRect[1] - root.bb.y) * root.k
                width: root.tintRect[2] * root.k
                height: root.tintRect[3] * root.k
                source: root.source
                clip: Qt.rect(root.tintRect[0], root.tintRect[1], root.tintRect[2], root.tintRect[3])
                accent: root.tintAccent
                amount: root.tintAmount
                spread: root.tintSpread
                variety: root.tintVariety
                mask: root.tintMask
                maskRev: root.tintMaskRev
            }

            // Light sheen toward the side that tilts away, like light on a glass screen.
            Rectangle {
                anchors.fill: parent
                opacity: 0.16 * Math.max(0, Math.min(1, root.lift))
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Math.max(0, -root.shiftX)) }
                    GradientStop { position: 0.5; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Math.max(0, root.shiftX)) }
                }
            }
        }
    }
}
