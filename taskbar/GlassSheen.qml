import QtQuick

// A soft highlight across the top of a glass panel. Put it as the first child of
// a rounded Rectangle; it follows the parent's shape.
Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: "transparent"
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#1cffffff" }
        GradientStop { position: 0.45; color: "#05ffffff" }
        GradientStop { position: 1.0; color: "#00ffffff" }
    }
}
