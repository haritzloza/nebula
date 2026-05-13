// shell.qml — entry point del HUD de Jarvis.
//
// Layer-shell overlay anclado bottom-center.
// pass-through input (no roba clicks).
// Lee estado por socket UNIX line-JSON desde el daemon.
//
// Arrancar:
//     qs -c jarvis

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: root

    // Estado global reactivo
    property string state: "idle"
    property real rms: 0.0
    property string transcript: ""
    property string response: ""
    property bool muted: false
    property string lastError: ""

    function isActive(): bool {
        return root.state === "listening" || root.state === "thinking" || root.state === "speaking";
    }

    // ─── Socket UNIX → estado ─────────────────────────────────────
    Socket {
        id: sock
        path: Qt.resolvedUrl(Quickshell.env("XDG_RUNTIME_DIR") + "/jarvis.sock")
        connected: true
        property string buffer: ""

        onConnectionStateChanged: {
            if (connectionState === Socket.Disconnected) {
                // Reintenta en 2 s
                reconnectTimer.start();
            }
        }

        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root._onLine(data)
        }
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: sock.connected = true
    }

    function _onLine(line: string): void {
        try {
            const j = JSON.parse(line);
            if (j.state !== undefined) root.state = j.state;
            if (j.rms !== undefined) root.rms = j.rms;
            if (j.transcript !== undefined) root.transcript = j.transcript;
            if (j.response !== undefined) root.response = j.response;
            if (j.error !== undefined) root.lastError = j.error;
            root.muted = (j.state === "muted");
        } catch (e) {
            console.warn("jarvis: bad line", line);
        }
    }

    // ─── Overlay ─────────────────────────────────────────────────
    PanelWindow {
        id: hud
        anchors {
            bottom: true
        }
        margins.bottom: 60
        exclusiveZone: 0
        // Pass-through al input cuando no es interactivo:
        WlrLayershell.keyboardFocus: WlrLayershell.None
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: 0

        color: "transparent"
        implicitWidth: 520
        implicitHeight: 180

        // Sólo visible si hay actividad o el panel ha sido recientemente activo
        visible: root.isActive() || root.muted || root.lastError !== ""

        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 8
            radius: 24
            color: "#cc101218"
            border.color: root.muted ? "#aa5b5b" : "#6cf"
            border.width: 1
            opacity: root.isActive() ? 1.0 : 0.65

            Behavior on opacity { NumberAnimation { duration: 200 } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // Orb central
                Orb {
                    id: orb
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 120
                    state: root.state
                    rms: root.rms
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Waveform
                    Waveform {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        active: root.state === "listening"
                        rms: root.rms
                    }

                    // Transcript / respuesta
                    Transcript {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        transcript: root.transcript
                        response: root.response
                        state: root.state
                    }
                }
            }
        }
    }
}
