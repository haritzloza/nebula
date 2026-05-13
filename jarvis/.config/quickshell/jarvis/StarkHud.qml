// StarkHud.qml — layout cinematográfico para el HUD de Jarvis.
//
// PanelWindow fullscreen (overlay layer-shell), pass-through al input.
// Centro: StarkOrb de ~420 px. Debajo: transcripción + respuesta con tipografía
// estilo HUD. Fondo: gradient radial muy sutil que se desvanece a los bordes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: hud

    property string state: "idle"
    property real rms: 0.0
    property string transcript: ""
    property string response: ""
    property bool muted: false
    property bool alwaysVisible: false

    function isActive(): bool {
        return state === "listening" || state === "thinking" || state === "speaking";
    }

    // Fullscreen overlay
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrLayershell.None
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: 0
    color: "transparent"

    visible: alwaysVisible || isActive() || muted

    // Sombra de fondo radial muy sutil (vignette inverso): la idea es que el
    // orb "ilumine" el centro de la pantalla sin tapar nada útil.
    Item {
        anchors.fill: parent
        opacity: hud.isActive() ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: width
            radius: width / 2
            color: "#0a1420"
            opacity: 0.15
        }
    }

    // Orb principal centrado
    StarkOrb {
        id: orb
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -50  // ligeramente arriba para dejar sitio al texto
        width: Math.min(parent.width, parent.height) * 0.32
        height: width
        state: hud.muted ? "muted" : hud.state
        rms: hud.rms

        // Fade-in dramático al activarse
        opacity: hud.isActive() || hud.alwaysVisible ? 1.0 : 0.35
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

        // Pequeña entrada de escala
        scale: hud.isActive() ? 1.0 : 0.92
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
    }

    // Bloque de texto debajo del orb
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: orb.bottom
        anchors.topMargin: 32
        width: Math.min(parent.width * 0.6, 720)
        spacing: 8

        // Estado actual (línea pequeña arriba, estilo HUD)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                switch (hud.state) {
                case "listening": return "·  E S C U C H A N D O  ·"
                case "thinking":  return "·  P R O C E S A N D O  ·"
                case "speaking":  return "·  R E S P O N D I E N D O  ·"
                case "muted":     return "·  S I L E N C I A D O  ·"
                default:           return "·  E N   E S P E R A  ·"
                }
            }
            color: "#9be8ff"
            opacity: 0.85
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.letterSpacing: 2
        }

        // Transcripción (lo que entendió de ti)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: hud.transcript ? "“" + hud.transcript + "”" : ""
            color: "#b8d8ff"
            opacity: 0.75
            font.family: "Inter"
            font.pixelSize: 14
            font.italic: true
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
            visible: text !== ""
        }

        // Respuesta (lo que Jarvis te dice)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: hud.response || (hud.state === "thinking" ? "" : "")
            color: "#eaf6ff"
            font.family: "Inter"
            font.pixelSize: 18
            font.weight: Font.Light
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 4
        }
    }
}
