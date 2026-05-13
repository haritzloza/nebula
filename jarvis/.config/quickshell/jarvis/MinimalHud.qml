// MinimalHud.qml — HUD ligero abajo-centro.
//
// Card semi-transparente con orb pequeño + waveform + transcripción inline.
// Pass-through al input. Visible solo durante interacción salvo alwaysVisible.

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
    property string lastError: ""
    property bool alwaysVisible: false

    function isActive(): bool {
        return state === "listening" || state === "thinking" || state === "speaking";
    }

    anchors { bottom: true }
    margins.bottom: 60
    exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrLayershell.None
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: 0

    color: "transparent"
    implicitWidth: 520
    implicitHeight: 180

    visible: alwaysVisible || isActive() || muted || lastError !== ""

    Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: 24
        color: "#cc101218"
        border.color: hud.muted ? "#aa5b5b" : "#6cf"
        border.width: 1
        opacity: hud.isActive() ? 1.0 : 0.65
        Behavior on opacity { NumberAnimation { duration: 200 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            Orb {
                id: orb
                Layout.preferredWidth: 120
                Layout.preferredHeight: 120
                state: hud.muted ? "muted" : hud.state
                rms: hud.rms
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Waveform {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    active: hud.state === "listening"
                    rms: hud.rms
                }

                Transcript {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    transcript: hud.transcript
                    response: hud.response
                    state: hud.state
                }
            }
        }
    }
}
