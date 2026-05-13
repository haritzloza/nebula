// Orb.qml — círculo pulsante con glow.
//
// Color por estado:
//   idle      → cyan tenue, pulso lento
//   listening → verde, escala según rms
//   thinking  → violeta, rotación interna
//   speaking  → naranja, ondas concéntricas

import QtQuick

Item {
    id: root
    property string state: "idle"
    property real rms: 0.0

    property color color: {
        switch (state) {
        case "listening": return "#6cf38a"
        case "thinking":  return "#b48cf3"
        case "speaking":  return "#f3a86c"
        case "muted":     return "#f37070"
        default:          return "#6cdcf3"
        }
    }

    // Anillo exterior (glow)
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * (0.85 + Math.min(root.rms * 4, 0.3))
        height: width
        radius: width / 2
        color: "transparent"
        border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.4)
        border.width: 2
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    // Anillo medio (pulso)
    Rectangle {
        id: ring
        anchors.centerIn: parent
        width: parent.width * 0.7
        height: width
        radius: width / 2
        color: "transparent"
        border.color: root.color
        border.width: 2

        SequentialAnimation on scale {
            running: root.state !== "idle" || true
            loops: Animation.Infinite
            NumberAnimation { from: 0.95; to: 1.05; duration: root.state === "thinking" ? 600 : 1100; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.05; to: 0.95; duration: root.state === "thinking" ? 600 : 1100; easing.type: Easing.InOutSine }
        }
    }

    // Núcleo
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.45
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.9) }
            GradientStop { position: 1.0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.2) }
        }

        // Rotación interna sólo en thinking
        RotationAnimation on rotation {
            running: root.state === "thinking"
            from: 0; to: 360
            loops: Animation.Infinite
            duration: 2400
        }
    }

    // Onda concéntrica cuando habla
    Rectangle {
        anchors.centerIn: parent
        visible: root.state === "speaking"
        color: "transparent"
        border.color: root.color
        border.width: 1.5
        radius: width / 2

        property real anim: 0.0
        width: parent.width * (0.5 + anim * 0.6)
        height: width
        opacity: 1.0 - anim

        NumberAnimation on anim {
            running: root.state === "speaking"
            from: 0; to: 1
            loops: Animation.Infinite
            duration: 1200
            easing.type: Easing.OutQuad
        }
    }
}
