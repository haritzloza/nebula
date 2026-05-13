// StarkOrb.qml — orb azul eléctrico estilo HUD de Iron Man / Stark.
//
// Capas (de fuera a dentro):
//   1. Glow externo radial (Canvas, gradient)
//   2. Anillo externo con 60 tick marks (rotación lenta CCW)
//   3. Anillo medio con 4 segmentos cardinales (rotación CW media)
//   4. Líneas de "scan" cruzando el orb (rotación rápida)
//   5. Anillo interno con 12 ticks (rotación variable según estado)
//   6. Núcleo radial blanco→azul
//   7. Ondas concéntricas cuando habla
//
// Color: Stark Blue eléctrico fijo. El estado se refleja en intensidad
// y velocidad de animaciones, no en cambio de color.

import QtQuick

Item {
    id: root
    property string state: "idle"
    property real rms: 0.0

    // Stark blue. Lo dejamos como propiedad por si quieres tunearlo.
    property color color: "#00d4ff"
    property color colorBright: "#9be8ff"
    property color colorDark: "#0066aa"

    // Intensidad global según estado
    property real intensity: {
        switch (state) {
        case "idle":      return 0.45
        case "listening": return 0.85 + Math.min(rms * 3, 0.15)
        case "thinking":  return 0.95
        case "speaking":  return 0.9 + Math.min(rms * 2, 0.1)
        case "muted":     return 0.25
        default:          return 0.5
        }
    }

    // ─── 1. Glow externo radial (Canvas) ─────────────────────────
    Canvas {
        id: glow
        anchors.centerIn: parent
        width: parent.width * 1.4
        height: width
        opacity: 0.55 * root.intensity
        Behavior on opacity { NumberAnimation { duration: 250 } }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const grad = ctx.createRadialGradient(cx, cy, width * 0.18, cx, cy, width * 0.5);
            grad.addColorStop(0.0, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.7));
            grad.addColorStop(0.45, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.18));
            grad.addColorStop(1.0, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.0));
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.arc(cx, cy, width * 0.5, 0, Math.PI * 2);
            ctx.fill();
        }
        Component.onCompleted: requestPaint()
    }

    // ─── 2. Anillo externo + tick marks ──────────────────────────
    Item {
        id: outerRing
        anchors.centerIn: parent
        width: parent.width
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55 * root.intensity)
            border.width: 1.5
        }

        // 60 ticks; cada 5 más largo (estilo brújula/HUD)
        Repeater {
            model: 60
            Item {
                width: outerRing.width
                height: outerRing.height
                Rectangle {
                    width: 2
                    height: index % 5 === 0 ? 14 : 6
                    color: Qt.rgba(
                        root.color.r, root.color.g, root.color.b,
                        (index % 5 === 0 ? 1.0 : 0.5) * root.intensity
                    )
                    x: outerRing.width / 2 - 1
                    y: 6
                }
                transform: Rotation {
                    origin.x: outerRing.width / 2
                    origin.y: outerRing.height / 2
                    angle: index * 6
                }
            }
        }

        RotationAnimation on rotation {
            running: true
            from: 0; to: -360
            loops: Animation.Infinite
            duration: 60000  // muy lento, casi imperceptible
        }
    }

    // ─── 3. Anillo medio + 4 segmentos cardinales ────────────────
    Item {
        id: midRing
        anchors.centerIn: parent
        width: parent.width * 0.78
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.7 * root.intensity)
            border.width: 1
        }

        // 4 segmentos en N/E/S/W
        Repeater {
            model: 4
            Item {
                width: midRing.width
                height: midRing.height
                Rectangle {
                    width: midRing.width * 0.22
                    height: 3
                    color: root.color
                    opacity: root.intensity
                    radius: 1
                    x: midRing.width / 2 - width / 2
                    y: -1.5
                }
                transform: Rotation {
                    origin.x: midRing.width / 2
                    origin.y: midRing.height / 2
                    angle: index * 90
                }
            }
        }

        RotationAnimation on rotation {
            running: true
            from: 360; to: 0
            loops: Animation.Infinite
            duration: root.state === "thinking" ? 8000 : 20000
        }
    }

    // ─── 4. Líneas de scan cruzando ──────────────────────────────
    Item {
        anchors.centerIn: parent
        width: parent.width * 0.85
        height: width
        opacity: root.state === "idle" ? 0.0 : 0.6

        Behavior on opacity { NumberAnimation { duration: 300 } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 1
            color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.5)
        }

        RotationAnimation on rotation {
            running: parent.opacity > 0
            from: 0; to: 360
            loops: Animation.Infinite
            duration: root.state === "thinking" ? 4000 : 8000
        }
    }

    // ─── 5. Anillo interno + 12 ticks (rota inverso) ─────────────
    Item {
        id: innerRing
        anchors.centerIn: parent
        width: parent.width * 0.55
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: root.color
            border.width: 1.5
            opacity: root.intensity
        }

        Repeater {
            model: 12
            Item {
                width: innerRing.width
                height: innerRing.height
                Rectangle {
                    width: 1
                    height: 6
                    color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.8 * root.intensity)
                    x: innerRing.width / 2 - 0.5
                    y: 3
                }
                transform: Rotation {
                    origin.x: innerRing.width / 2
                    origin.y: innerRing.height / 2
                    angle: index * 30
                }
            }
        }

        RotationAnimation on rotation {
            running: true
            from: 0; to: 360
            loops: Animation.Infinite
            duration: root.state === "thinking" ? 3500 : 14000
        }
    }

    // ─── 6. Núcleo radial blanco → azul ──────────────────────────
    Canvas {
        id: core
        anchors.centerIn: parent
        width: parent.width * 0.32
        height: width
        opacity: root.intensity

        property real pulse: 1.0
        SequentialAnimation on pulse {
            running: true
            loops: Animation.Infinite
            NumberAnimation { from: 0.95; to: 1.05; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.05; to: 0.95; duration: 1400; easing.type: Easing.InOutSine }
        }
        scale: pulse
        Behavior on opacity { NumberAnimation { duration: 200 } }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2;
            const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, width * 0.5);
            grad.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.95));
            grad.addColorStop(0.25, Qt.rgba(root.colorBright.r, root.colorBright.g, root.colorBright.b, 0.85));
            grad.addColorStop(0.6, Qt.rgba(root.color.r, root.color.g, root.color.b, 0.7));
            grad.addColorStop(1.0, Qt.rgba(root.colorDark.r, root.colorDark.g, root.colorDark.b, 0.15));
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.arc(cx, cy, width * 0.5, 0, Math.PI * 2);
            ctx.fill();
        }
        Component.onCompleted: requestPaint()
    }

    // ─── 7. Ondas concéntricas cuando habla ──────────────────────
    Repeater {
        model: root.state === "speaking" ? 2 : 0
        Rectangle {
            anchors.centerIn: parent
            color: "transparent"
            border.color: root.color
            border.width: 2
            radius: width / 2

            property real anim: index * 0.5  // desfase entre las 2 ondas
            width: root.width * (0.4 + anim * 0.7)
            height: width
            opacity: 1.0 - anim

            NumberAnimation on anim {
                running: root.state === "speaking"
                from: index * 0.5; to: 1.0 + index * 0.5
                loops: Animation.Infinite
                duration: 1600
                easing.type: Easing.OutQuad
            }
        }
    }
}
