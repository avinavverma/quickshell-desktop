// A patch of the wallpaper re-hued toward an accent colour. Sits exactly over the
// same pixels of the flat wallpaper, so with amount 0 it is invisible.
import QtQuick

Item {
    id: root
    property url source
    property rect clip                 // the patch, in image pixels
    property color accent: "#e5484d"
    property real amount: 0            // 0 = original colours, 1 = fully recoloured
    property real spread: 0.45
    property real variety: 0.0         // 0 = exactly the accent colour, 1 = original colour variety
    property real baseHue: 0.88
    property url mask                  // eye-mask.png: alpha = where to recolour (optional)
    property int maskRev: 0            // bump to reload the mask after it was repainted
    onMaskRevChanged: { const m = mask; maskImg.source = ""; maskImg.source = m }

    visible: amount > 0.002 && (!mask.toString() || maskImg.status !== Image.Loading)

    Image {
        id: img
        visible: false
        source: root.source
        sourceClipRect: root.clip
        // Decode the patch near its on-screen size (the full 4K crop would be wasted).
        mipmap: true
        smooth: true
        asynchronous: true
        cache: false
    }

    Image {
        id: maskImg
        visible: false
        source: root.mask
        smooth: true
        cache: false
    }

    ShaderEffect {
        anchors.fill: parent
        property var src: img
        property real hue: Math.max(0, root.accent.hsvHue)
        property real sat: Math.min(1.25, 0.55 + root.accent.hsvSaturation * 0.8)
        property real spread: root.spread
        property real variety: root.variety
        property color tint: root.accent
        property real baseHue: root.baseHue
        property real amount: root.amount
        property var maskTex: maskImg
        property real useMask: maskImg.status === Image.Ready ? 1 : 0
        fragmentShader: Qt.resolvedUrl("shaders/hueshift.frag.qsb")
    }
}
